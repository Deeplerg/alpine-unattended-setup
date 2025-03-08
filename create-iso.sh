#!/bin/bash

set -o errexit
set -o nounset

# close standard input
exec 0<&-

. common.sh

setup_collection=".setup"


download_url_base=https://dl-cdn.alpinelinux.org/alpine/v3.21/releases/x86_64/alpine-virt-3.21.3-x86_64
download_url_image=${download_url_base}.iso
download_url_sha256=${download_url_image}.sha256
download_file_image=$(basename $download_url_image)
download_file_sha256=$(basename $download_url_sha256)

if [ ! -f "$download_file_image" ]; then
    wget $download_url_image
fi
wget $download_url_sha256
sha256sum -c $download_file_sha256

rm $download_file_sha256

mkdir -p ovl/etc/auto-setup-alpine

generate_password_hash () {
    local password=${1-}

    if [ -z "${password-}" ]; then
        echo "Usage: generate_password_hash [password]"
        return 1
    fi

    if [ "$password" = "disable" ]; then
        echo "!"
    else
        echo $password | openssl passwd -stdin
    fi
}

# generate password if it's not set and return it, otherwise return passed password
generate_password_if_unset () {
    local file=${1-}
    local password=${2-}

    if [ -z "$file" ]; then
        echo "Usage: generate_password_if_unset [output file] [password (optional)]"
    fi

    if [ -z "${password-}" ]; then
        password=$(openssl rand -hex 128)
    fi
    echo $password | tee $file
}

for ((i = 0; ; i++)); do
    if ! collection_any $setup_collection "$i"; then
        break
    fi

    repeat="$(get_value_from_collection $setup_collection $i repeat)"
    if [ -z "${repeat-}" ]; then
        repeat=1
    fi

    for ((j = 0; j < repeat; j++)); do
        name="$(get_value_from_collection $setup_collection $i name)"
        hostname="$(get_value_from_collection $setup_collection $i hostname)"
        timezone="$(get_value_from_collection $setup_collection $i timezone)"
        username="$(get_value_from_collection $setup_collection $i username)"
        dnsaddr="$(get_value_from_collection $setup_collection $i dnsaddr)"
        dnssearch="$(get_value_from_collection $setup_collection $i dnssearch)"
        bootsize="$(get_value_from_collection $setup_collection $i bootsize)"

        if [ -z "${name-}" ]; then
            name="alpine-auto"
        fi

        if [ -z "${hostname-}" ]; then
            hostname="alpine-auto"
        fi

        if [ "$repeat" -gt 1 ]; then
            name="${name}-$j"
            hostname="${hostname}-$j"
        fi

        if [ -z "${timezone-}" ]; then
            timezone="UTC"
        fi

        if [ -z "${username-}" ]; then
            username="alpine"
        fi

        if [ -z "${dnsaddr-}" ]; then
            dnsaddr="1.1.1.1 8.8.8.8"
        fi

        if [ -z "${dnssearch-}" ]; then
            dnssearch="localdomain"
        fi

        if [ -z "${bootsize-}" ]; then
            bootsize=200
        fi

        sshkey="$(get_value_from_collection $setup_collection $i sshkey)"
        user_password="$(get_value_from_collection $setup_collection $i user-password)"
        root_password="$(get_value_from_collection $setup_collection $i root-password)"

        mkdir -p "results/$name"

        if [ -z "${sshkey-}" ]; then
            rm -f "results/$name/id_ed25519"
            ssh-keygen -t ed25519 -f "results/$name/id_ed25519" -C "" -N ""
            sshkey=$(cat "results/$name/id_ed25519.pub")
        fi
        echo $sshkey > "results/$name/id_ed25519.pub"

        user_password=$(generate_password_if_unset "results/$name/user-password" $user_password)
        root_password=$(generate_password_if_unset "results/$name/root-password" $root_password)
        generate_password_hash $user_password > ovl/etc/auto-setup-alpine/user-password-hash
        generate_password_hash $root_password > ovl/etc/auto-setup-alpine/root-password-hash

        echo $username > ovl/etc/auto-setup-alpine/username

        rm -f "ovl/etc/auto-setup-alpine/answers"
        while read line
        do
            eval echo "$line" >> "ovl/etc/auto-setup-alpine/answers"
        done < "ovl-config/answers-template"

        substitute_template "ovl-config/answers-template" "ovl/etc/auto-setup-alpine/answers"
        substitute_template "ovl-config/disk-answers-template" "ovl/etc/auto-setup-alpine/disk-answers"

        rm -f results/$name/apkovl.tar.gz
        tar --owner=0 --group=0 -czf results/$name/apkovl.tar.gz -C ovl .

        rm -f results/$name/image.iso
        xorriso \
            -indev $download_file_image \
            -outdev results/$name/image.iso \
            -map results/$name/apkovl.tar.gz /localhost.apkovl.tar.gz \
            -boot_image any replay
    done
done

