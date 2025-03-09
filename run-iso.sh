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

collection=".run"


start_kvm () {
    local disk_path=${1-}
    local memory=${2-}
    local cpu=${3-}
    local local_port=${4-}
    local iso_path=${5-}

    if [[ -z ${1-} || -z ${2-} || -z ${3-} || -z ${4-} ]]; then
        echo "Usage: start_kvm [disk_path] [memory] [cpu] [local_port] [iso_path (optional)]"
        return 1
    fi

    if [ -n "$iso_path" ]; then
        iso_command_part="-cdrom $iso_path"
    fi
    
    # shellcheck disable=SC2086
    qemu-system-x86_64 \
        -no-reboot \
        -m "$memory" \
        -smp "$cpu" \
        -cpu host \
        -device virtio-scsi-pci,id=scsi \
        -device scsi-hd,drive=disk0 \
        -drive file="$disk_path",format=raw,cache=none,id=disk0,if=none \
        ${iso_command_part-} \
        -enable-kvm \
        -device virtio-net-pci,netdev=net0 \
        -netdev user,id=net0,hostfwd=tcp::"$local_port"-:22 \
        -nographic > /dev/null
}

declare -a kvm_pids

for ((i = 0; ; i++)); do
    if ! collection_any $collection "$i"; then
        break
    fi

    repeat="$(get_value_from_collection_or_default $collection $i "repeat" 1)"
    disk_size="$(get_value_from_collection_or_default $collection $i "disk-size" 384)"
    memory="$(get_value_from_collection_or_default $collection $i "memory" 512)"
    cpu="$(get_value_from_collection_or_default $collection $i "cpu" 1)"
    first_boot="$(get_value_from_collection_or_default $collection $i "first-boot" true)"
    hypervisor="$(get_value_from_collection $collection $i "hypervisor")"

    if [ -z "${hypervisor-}" ]; then
        echo "Hypervisor not set. Add \"hypervisor:\"."
        exit 1
    fi

    if [ "$hypervisor" = "kvm" ]; then
        kvm_port="$(get_value_from_collection_or_default "$collection" $i "kvm.local-ssh-port-start" "32000")"
    fi

    for ((j = 0; j < repeat; j++)); do
        name="$(get_value_from_collection_or_default $collection $i "name" "alpine-auto")"

        if [ "$repeat" -gt 1 ]; then
            name="${name}-$j"
        fi

        disk="results/$name/image.raw"
        image="results/$name/image.iso"
        if [ "$first_boot" = "true" ]; then
            rm -f "$disk"
            truncate -s "$disk_size"M "$disk"
            install_iso="$image"
        fi

        case "$hypervisor" in
            "kvm")
                # shellcheck disable=SC2086
                start_kvm $disk $memory $cpu $kvm_port ${install_iso-} &
                kvm_pid=$!
                kvm_pids[j]=$kvm_pid

                ((kvm_port+=1))
                ;;
            
            *)
                echo "Unknown hypervisor"
                exit 1
                ;;
        esac
    done
done

if [ ${#kvm_pids[@]} -gt 0 ]; then
    echo "Waiting for KVM VMs to finish..."
    for pid in "${kvm_pids[@]}"; do
        wait "$pid"
        echo "[PID $pid] has finished"
    done
fi