#!/bin/bash

set -o errexit
set -o nounset

# close standard input
exec 0<&-

. common.sh

collection=".run"

start_kvm () {
    local disk_path=${1-}
    local memory=${2-}
    local cpu=${3-}
    local netprefix=${4-}
    local iso_path=${5-}

    if [[ -z ${1-} || -z ${2-} || -z ${3-} || -z ${4-} ]]; then
        echo "Usage: start_kvm [disk_path] [memory] [cpu] [netprefix (x.x.x)] [iso_path (optional)]"
        return 1
    fi

    if [ ! -z "$iso_path" ]; then
        iso_command_part="-cdrom $iso_path"
    fi
    
    qemu-system-x86_64 \
        -no-reboot \
        -m $memory \
        -smp $cpu \
        -cpu host \
        -device virtio-scsi-pci,id=scsi \
        -device scsi-hd,drive=disk0 \
        -drive file=$disk_path,format=raw,cache=none,id=disk0,if=none \
        ${iso_command_part-} \
        -enable-kvm \
        -device virtio-net-pci,netdev=net0 \
        -netdev user,id=net0,net=$netprefix.0/24,dhcpstart=$netprefix.10 \
        -nographic > /dev/null
}

declare -a kvm_pids

for ((i = 0; ; i++)); do
    if ! collection_any $collection "$i"; then
        break
    fi

    repeat="$(get_value_from_collection $collection $i repeat)"
    if [ -z "${repeat-}" ]; then
        repeat=1
    fi

    for ((j = 0; j < repeat; j++)); do
        name="$(get_value_from_collection $collection $i name)"
        hypervisor="$(get_value_from_collection $collection $i hypervisor)"
        disk_size="$(get_value_from_collection $collection $i disk-size)"
        memory="$(get_value_from_collection $collection $i memory)"
        cpu="$(get_value_from_collection $collection $i cpu)"
        first_boot="$(get_value_from_collection $collection $i first-boot)"

        if [ -z "${name-}" ]; then
            name="alpine-auto"
        fi

        if [ "$repeat" -gt 1 ]; then
            name="${name}-$j"
        fi

        if [ -z "${hypervisor-}" ]; then
            echo "Hypervisor not set. Add \"hypervisor:\"."
            exit 1
        fi

        if [ -z "${disk_size-}" ]; then
            disk_size=384
        fi

        if [ -z "${memory-}" ]; then
            memory=512
        fi

        if [ -z "${cpu-}" ]; then
            cpu=1
        fi

        if [ -z "${first_boot-}" ]; then
            first_boot=true
        fi

        disk="results/$name/image.raw"
        if [ "$first_boot" = "true" ]; then
            rm -f $disk
            truncate -s "$disk_size"M $disk
            install_iso="results/$name/image.iso"
        fi

        case "$hypervisor" in
            "kvm")
                netprefix="$(get_value_from_collection "$collection" $i kvm.netprefix)"
                if [ -z "${netprefix-}" ]; then
                    netprefix="10.75"
                fi
                netprefix="$netprefix.$j"

                start_kvm $disk $memory $cpu $netprefix ${install_iso-} &
                kvm_pid=$!
                kvm_pids[$j]=$kvm_pid
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
    for pid in ${kvm_pids[@]}; do
        wait $pid
        echo "[PID $pid] has finished"
    done
fi