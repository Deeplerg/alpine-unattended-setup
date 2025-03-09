#!/bin/bash

set -o errexit
set -o nounset

# close standard input
exec 0<&-

source common.sh

# fail if we didn't get variables and disable spellcheck warnings in the process
echo "${auto_setup_alpine_folder:?}" > /dev/null
echo "${results_folder:?}" > /dev/null
echo "${overlay_config_folder:?}" > /dev/null
echo "${ovl_folder:?}" > /dev/null

collection=".setup"


download_url_base=https://dl-cdn.alpinelinux.org/alpine/v3.21/releases/x86_64/alpine-virt-3.21.3-x86_64
download_url_image=${download_url_base}.iso
download_url_sha256=${download_url_image}.sha256
download_file_image=$(basename $download_url_image)
download_file_sha256=$(basename $download_url_sha256)

if [ ! -f "$download_file_image" ]; then
    wget $download_url_image
fi
wget $download_url_sha256
sha256sum -c "$download_file_sha256"

rm "$download_file_sha256"

mkdir -p "$auto_setup_alpine_folder"

generate_password_hash () {
    local password=${1-}

    if [ -z "${password-}" ]; then
        echo "Usage: generate_password_hash [password]"
        return 1
    fi

    if [ "$password" = "disable" ]; then
        echo "!"
    else
        echo "$password" | openssl passwd -stdin
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
    echo "$password" | tee "$file"
}

for ((i = 0; ; i++)); do
    if ! collection_any $collection "$i"; then
        break
    fi

    repeat="$(get_value_from_collection_or_default $collection $i "repeat" 1)"
    username="$(get_value_from_collection_or_default $collection $i "username" "alpine-auto")"
    encrypt="$(get_value_from_collection_or_default $collection $i "encrypt" false)"
    lvm="$(get_value_from_collection_or_default $collection $i "lvm" false)"
    # shellcheck disable=SC2034
    dnsaddr="$(get_value_from_collection_or_default $collection $i "dnsaddr" "1.1.1.1 8.8.8.8")"
    # shellcheck disable=SC2034
    dnssearch="$(get_value_from_collection_or_default $collection $i "dnssearch" "localdomain")"
    # shellcheck disable=SC2034
    bootsize="$(get_value_from_collection_or_default $collection $i "bootsize" 200)"
    # shellcheck disable=SC2034
    timezone="$(get_value_from_collection_or_default $collection $i "timezone" "UTC")"

    for ((j = 0; j < repeat; j++)); do
        name="$(get_value_from_collection_or_default $collection $i "name" "alpine-auto")"
        hostname="$(get_value_from_collection_or_default $collection $i "hostname" "alpine-auto")"

        if [ "$repeat" -gt 1 ]; then
            name="${name}-$j"
            hostname="${hostname}-$j"
        fi

        sshkey="$(get_value_from_collection $collection $i "sshkey")"
        user_password="$(get_value_from_collection $collection $i "user-password")"
        root_password="$(get_value_from_collection $collection $i "root-password")"

        current_results_folder="$results_folder/$name"

        mkdir -p "$current_results_folder"

        if [ -z "${sshkey-}" ]; then
            rm -f "$current_results_folder/id_ed25519"
            ssh-keygen -t ed25519 -f "$current_results_folder/id_ed25519" -C "" -N ""
            sshkey=$(cat "$current_results_folder/id_ed25519.pub")
        fi
        echo "$sshkey" > "$current_results_folder/id_ed25519.pub"

        user_password=$(generate_password_if_unset "$current_results_folder/user-password" "${user_password:-}")
        root_password=$(generate_password_if_unset "$current_results_folder/root-password" "${root_password:-}")
        generate_password_hash "$user_password" > "$auto_setup_alpine_folder/user-password-hash"
        generate_password_hash "$root_password" > "$auto_setup_alpine_folder/root-password-hash"
        
        if [ "$encrypt" = true ]; then
            encrypt_password="$(get_value_from_collection $collection $i "encrypt-password")"
            encrypt_password=$(generate_password_if_unset "$current_results_folder/encrypt_password" "${encrypt_password:-}")
            echo "$encrypt_password" > "$auto_setup_alpine_folder/encrypt-password"
        fi

        echo "$username" > "$auto_setup_alpine_folder/username"

        substitute_template "$overlay_config_folder/answers-template" "$auto_setup_alpine_folder/answers"
        substitute_template "$overlay_config_folder/disk-answers-template" "$auto_setup_alpine_folder/disk-answers"

        echo "$encrypt" > "$auto_setup_alpine_folder/encrypt"
        echo "$lvm" > "$auto_setup_alpine_folder/lvm"
        
        image_file="$current_results_folder/image.iso"
        overlay_file="$current_results_folder/apkovl.tar.gz"
        
        rm -f "$overlay_file" # remove existing overlay (if it exists)
        tar --owner=0 --group=0 -czf "$overlay_file" -C "$ovl_folder" .
        
        rm -f "$image_file"
        xorriso \
            -indev "$download_file_image" \
            -outdev "$image_file" \
            -map "$overlay_file" /localhost.apkovl.tar.gz \
            -boot_image any replay
    done
done

