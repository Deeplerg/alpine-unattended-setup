# alpine-unattended-setup

## About
A set of scripts to automate the initial installation of Alpine Linux.

## Requirements
- xorriso
- yq
- openssl
- ssh-keygen
- bash
- tar
- wget
- sha256sum

At least one of supported hypervisors:
- qemu-system-x86_64 (KVM)

## Basic usage
```sh
git clone https://github.com/Deeplerg/alpine-unattended-setup --recursive
# configure config.yaml to your liking
./create-iso.sh
./run-iso.sh
# .raw disk files are placed in results/$machine_name/
```

## How it works
There are two main "client-side" scripts: `create-iso.sh` and `run-iso.sh`.

The `auto-setup-alpine.start` is a script that runs inside the VM on boot.

In general, the workflow is as follows:
- `create-iso.sh` downloads and repackages the official Alpine .iso (virt)
- `run-iso.sh` creates and runs a VM with this .iso attached
- `auto-setup-alpine.start` runs `setup-alpine` (and other `setup-*` scripts), configuring the system and 
setting up the disk.

### `create-iso.sh`
- Downloads Alpine virt x86 .iso from the official CDN, or reuses it if it's already present in the current directory
- Downloads the .sha256 file and verifies the .iso
- Walks through each machine defined in the `.setup` section of `config.yaml` and populates `ovl/etc/auto-setup-alpine`
with files carrying the necessary configuration
- Archives the `ovl` folder into .tar.gz and places it inside the new .iso 
(Alpine then picks up this 
[overlay file](https://wiki.alpinelinux.org/wiki/Alpine_local_backup#Creating_and_saving_an_apkovl_from_a_remote_host) 
on boot)
- The resulting .iso (among other artifacts) is placed inside the corresponding `results/$machine_name` folder.

### `run-iso.sh`
- Walks through each machine defined in the `.run` section of `config.yaml` and runs each of them in parallel 
in separate VMs, using the .iso created by `create-iso.sh`
- Waits for the VMs to shut down.

### `auto-setup-alpine.start`
This script is run on first boot of the machine.

It:
- Runs `setup-alpine` with an [answerfile](https://wiki.alpinelinux.org/wiki/Alpine_setup_scripts#setup-alpine)
- However, this script is rigged to intentionally fail on the last step, `setup-disk`. 
This is because the answerfile isn't flexible enough and doesn't accept all the options that `setup-disk` does.
This also allows us to do other things before copying system files onto a new disk:
- Runs `setup-dns` (because `setup-alpine` populates it with DHCP-provided values if DHCP networking is configured)
- Sets up passwords
- Runs `setup-disk` with specific configurable environment variables, such as `BOOT_SIZE`
- Configures dropbear if requested (see configuration) for remotely decrypting disk via SSH.
- Shuts down upon completion. 

## Configuration

### `config.yaml`
The main configuration file.

In `.setup` and `.run`, defines collections of machines to create .iso files for and run.

#### `.setup.[]`
- `name`: machine name to be used in setup scripts
- `repeat`: how many .iso files to create 
(the current machine number gets appended to `results/$machine_name`, e.g. `results/alpine-auto-4/`)
- `hostname` 
- `timezone`: e.g. `"UTC"`, `"Europe/London"`. 
See [List of tz database time zones](https://en.wikipedia.org/wiki/List_of_tz_database_time_zones) and
[setup-timezone](https://wiki.alpinelinux.org/wiki/Alpine_setup_scripts#setup-timezone)
- `username`: default admin user to be configured
- `dnsaddr`: a space-separated list of DNS servers
- `dnssearch`: *search domain name*. See "search" in [man resolv.conf](https://linux.die.net/man/5/resolv.conf) 
- `bootsize`: size of the boot partition
- `sshkey`: public ssh key. If empty, a new `ed25519` key will be generated.
- `user-password`: password of the default admin user. 
If empty, a random 128-character password will be generated.
If `"disable"`, password authentication is disabled.
- `root-password`: same as `user-password` but for root.
- `encrypt`: whether to encrypt the system partition.
- `encrypt-password`: encryption password. If empty, a random 128-character password will be generated.
- `lvm`: whether to build an LVM group.
- `dropbear`: whether to configure dropbear. Dropbear will run on boot (initramfs stage)
with cryptsetup password prompt as shell. This way, it will be possible to unlock encrypted system partition
remotely and securely via SSH, without having to input the encryption password in VNC
or having to store it in the boot partition.
- `dropbear-sshkey`: public ssh key for dropbear. If empty, a new `ed25519` key will be generated.
This option is separate from `"sshkey"`.
- `dropbear-debug`: whether to configure the boot menu in a way that makes troubleshooting possible.
If true, the boot menu will be visible during startup.
- `dropbear-debug-timeout`: boot menu timeout in seconds.

#### `.run.[]`
- `name`: machine name
- `repeat`: should match `.setup.[].repeat` - how many VMs to run
- `hypervisor`: supported values:
    - `"kvm"`
- `disk-size`: size of the .raw disk to be created and attached to the VM, in MB
- `memory`: RAM in MB
- `cpu`: vCPU count
- `first-boot`: whether to attach the .iso to the VM (`"first-boot": true`) or not (`"first-boot": false`).
  Useful for setup after the VM has been configured.

Hypervisor-specific:
- `kvm`
    - `local-ssh-port-start`: a TCP localhost port to be forwarded to port 22 on the VM.
      If `repeat > 1`, this value is incremented for each machine.

### `ovl-config`
Configuration files for `ovl`.

#### `answers-template`
Answerfile template for `setup-alpine`. Populated with variables based on `config.yaml`.

#### `disk-answers-template`
Answerfile template for `setup-disk`. Populated with variables based on `config.yaml`.

#### `interfaces`
The (future) contents of `/etc/network/interfaces`.

#### `dropbear/mkinitfs.conf`:
If dropbear is enabled, use this configuration file with mkinitfs (for initramfs)

### `ovl/etc/apk/repositories`
The initial contents of `/etc/apk/repositories` used for setup.

### Generated artifacts (`results/`)
If `repeat = 1`, a single `results/$machine_name` folder is created.

If `repeat > 1`, multiple `results/$machine_name-$i` folders are created, 
with `$i` being the machine number. For example, `results/alpine-auto-0/`,`results/alpine-auto-1/`, etc.   

Each machine's folder contains:
- `apkovl.tar.gz`: the overlay file included in the .iso
- `image.iso`: the .iso image attached to the VM
- `image.raw`: the .raw disk file attached to the VM
- `user-password`: default user's password
- `root-password`: root password
- `encrypt_password`: disk encryption password
- `id_ed25519`: private ssh key
- `id_ed25519.pub`: public ssh key
- `dropbear-id_ed25519`: private ssh key for dropbear
- `dropbear-id_ed25519.pub`: public ssh key for dropbear


## Credits
**Based on this guide: https://www.skreutz.com/posts/unattended-installation-of-alpine-linux/**

The original repo of alpine-initramfs-dropbear: https://github.com/mk-f/alpine-initramfs-dropbear

[Alpine ❤️](https://alpinelinux.org)