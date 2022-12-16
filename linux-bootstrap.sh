#!/bin/bash

# HELP --------------------------------------------------

# check if the --help parameter is used
if [ "$1" == "--help" ]
  then echo "Usage instructions:
  ./linux-bootstrap.sh [--distro (arch/gentoo)] [--disk DEVICE] [--mountpoint MOUNTPOINT] [--hostname HOSTNAME] [--timezone TIMEZONE] [--locale LOCALE] [--firmware (efi/bios/none)] [--rootfs (ext4/btrfs)] [--bootfs (vfat/ext4)]"
  exit
fi

# -------------------------------------------------------
# PARAMS ------------------------------------------------

# Ustawienie domyślnych wartości parametrów
MOUNTPOINT="/mnt/linux-bootstrap"
HOSTNAME=""
LOCALE="en_US.UTF-8"
FIRMWARE="efi"
ROOTFS="ext4"
BOOTFS="vfat"

# Przetwarzanie parametrów
while [ $# -gt 0 ]; do
  case $1 in
    --distro) DISTRO="$2"; shift;;
    --disk) DISK="$2"; shift;;
    --mountpoint) MOUNTPOINT="$2"; shift;;
    --hostname) HOSTNAME="$2"; shift;;
    --timezone) TIMEZONE="$2"; shift;;
    --locale) LOCALE="$2"; shift;;
    --firmware) FIRMWARE="$2"; shift;;
    --rootfs) ROOTFS="$2"; shift;;
    --bootfs) BOOTFS="$2"; shift;;
    *) echo "Invalid option: $1" >&2; exit 1;;
  esac
  shift
done

if [ -z "$HOSTNAME" ]
then
  HOSTNAME="$DISTRO"
fi

# Wypisanie przetworzonych parametrów
echo "DISTRO=$DISTRO"
echo "DISK=$DISK"
echo "MOUNTPOINT=$MOUNTPOINT"
echo "HOSTNAME=$HOSTNAME"
echo "TIMEZONE=$TIMEZONE"
echo "LOCALE=$LOCALE"
echo "FIRMWARE=$FIRMWARE"
echo "ROOTFS=$ROOTFS"
echo "BOOTFS=$BOOTFS"
echo "----------------------------------------"

# -------------------------------------------------------
# VALIDATION --------------------------------------------

if [ "$EUID" -ne 0 ]; then
  echo "Root privileges are required to run this script"; exit
fi
if [ "$DISTRO" != "arch" ] && [ "$DISTRO" != "gentoo" ]; then
  echo "Error: Invalid value for the --distro parameter. Must be either arch or gentoo."; exit
fi
if [ -z "$DISK" ] || [ ! -e "$DISK" ]; then
  echo "Invalid device. The specified device does not exist or is not a block device."; exit
fi
if [ "$(ls -A "$MOUNTPOINT")" ]; then
  echo "The mountpoint directory is not empty. Please specify an empty directory as the mountpoint."; exit
fi
if ! [[ "$HOSTNAME" =~ ^[a-zA-Z0-9]*$ ]]; then
  echo "Invalid hostname. The hostname can only contain alphanumeric characters."; exit
fi
if [ -z "$TIMEZONE" ] || [ ! -f "/usr/share/zoneinfo/$TIMEZONE" ]; then
  echo "Invalid timezone. Please specify a valid timezone from the list in /usr/share/zoneinfo."; exit
fi
if [ -z "$LOCALE" ] || [[ "$(locale -a | grep -w "$LOCALE")" != "" ]]; then
  echo "Invalid locale. The specified locale does not exist."; exit
fi
if [ "$FIRMWARE" != "efi" ] && [ "$FIRMWARE" != "bios" ] && [ "$FIRMWARE" != "none" ]; then
  echo "Error: Invalid value for the --firmware parameter. Must be one of: efi, bios, none."; exit
fi
if [ "$ROOTFS" != "ext4" ] && [ "$ROOTFS" != "btrfs" ]; then
    echo "Error: Invalid value for the --rootfs parameter. Must be either ext4 or btrfs."; exit
fi
if [ "$BOOTFS" != "vfat" ] && [ "$BOOTFS" != "ext4" ]; then
    echo "Error: Invalid value for the --bootfs parameter. Must be either vfat or ext4."; exit
fi

# -------------------------------------------------------
# PREPARING DISK ----------------------------------------

# wipe disk space
dd if=/dev/zero of=$DISK bs=10M status=progress 2>&1

# format the disk using fdisk
printf "g\nn\n1\n\n+128M\nn\n2\n\n\nt\n1\n4\nw\n" | fdisk $DISK

# -------------------------------------------------------
# FORMAT PARTITIONS -------------------------------------

# check if the root partition type is valid
if [ "$ROOTFS" == "ext4" ]
  then
    # format the root partition as ext4
    mkfs.ext4 "${DISK}2"
fi

if [ "$ROOTFS" == "btrfs" ]
  then
    # format the root partition as btrfs
    mkfs.btrfs "${DISK}2"
fi

# check if the boot partition type is valid
if [ "$BOOTFS" == "fat" ]
  then
    # format the boot partition as fat
    mkfs.fat "${DISK}1"
fi

if [ "$BOOTFS" == "ext4" ]
  then
    # format the boot partition as ext4
    mkfs.ext4 "${DISK}1"
fi

# -------------------------------------------------------
# MOUNTING PARTITIONS -----------------------------------

# create the mountpoint directory if it does not exist
if [ ! -d "$MOUNTPOINT" ]
  then mkdir -p "$MOUNTPOINT"
fi

# mount the second partition of the disk to the mountpoint directory
mount "${DISK}2" "$MOUNTPOINT"

# create the boot directory in the mountpoint directory
mkdir "$MOUNTPOINT/boot"

# mount the first partition of the disk to the boot directory
mount "${DISK}1" "$MOUNTPOINT/boot"

# -------------------------------------------------------
# BOOTSTRAPING ------------------------------------------

# create the bootstrap function
bootstrap() {
    # check the validity of the --distro parameter value
    if [ "$DISTRO" = "arch" ]
    then
        # placeholder for Arch-specific instructions
        echo "Arch bootstrap to be implemented"
    elif [ "$DISTRO" = "gentoo" ]
    then
        # download the latest stage3 tarball for gentoo amd64
        
        # Pobranie tekstu z podanego URL i wyciągnięcie z niego informacji o ścieżce do pliku stage3 i jego rozmiarze
        STAGE3_PATH_SIZE=$(curl -L https://gentoo.osuosl.org/releases/amd64/autobuilds/latest-stage3-amd64-openrc.txt | grep -v '^#')
        STAGE3_PATH=$(echo $STAGE3_PATH_SIZE | cut -d ' ' -f 1)
        # Wygenerowanie pełnej ścieżki do pliku tar.xz podanego w pliku tekstowym
        STAGE3_URL="https://gentoo.osuosl.org/releases/amd64/autobuilds/$STAGE3_PATH"
        # Pobieranie
        curl -L "$STAGE3_URL" -o "$MOUNTPOINT/stage3-amd64.tar.xz"
        # extract the tarball to the root partition
        tar xpvf "$MOUNTPOINT/stage3-amd64.tar.xz" --xattrs-include='*.*' --numeric-owner -C "$MOUNTPOINT"
        sed -i 's/^COMMON_FLAGS="/COMMON_FLAGS="-march=native /' "${MOUNTPOINT}/etc/portage/make.conf"
        echo 'MAKEOPTS="-j4"' >> "${MOUNTPOINT}/etc/portage/make.conf"
        echo 'ACCEPT_LICENSE="*"' >> "${MOUNTPOINT}/etc/portage/make.conf"
        cp --dereference /etc/resolv.conf "${MOUNTPOINT}/etc/"
    else
        echo "Invalid Linux distribution. Allowed options are arch or gentoo."
        exit
    fi
}

# call the bootstrap function
bootstrap

# -------------------------------------------------------
# CONFIGURATION -----------------------------------------

# Setup hostname
echo "$HOSTNAME" >> "${MOUNTPOINT}/etc/hostname"

# Setup locale
sed -i "/$LOCALE/s/^#//g" ${MOUNTPOINT}/etc/locale.gen
echo "LANG=$LOCALE" >> ${MOUNTPOINT}/etc/locale.conf

# -------------------------------------------------------
# PREPARE FOR CHROOT ------------------------------------

# Prepare environment for CHRoot
prepareenv() {
    # check the validity of the --distro parameter value
    if [ "$DISTRO" = "arch" ]
    then
        # placeholder for Arch-specific instructions
        echo "Arch chroot setup to be implemented"
    elif [ "$DISTRO" = "gentoo" ]
    then
        mount --types proc /proc ${MOUNTPOINT}/proc
        mount --rbind /sys ${MOUNTPOINT}/sys
        mount --make-rslave ${MOUNTPOINT}/sys
        mount --rbind /dev ${MOUNTPOINT}/dev
        mount --make-rslave ${MOUNTPOINT}/dev
        mount --bind /run ${MOUNTPOINT}/run
        mount --make-slave ${MOUNTPOINT}/run
    else
        echo "Invalid Linux distribution. Allowed options are arch or gentoo."
        exit
    fi
}

prepareenv

# -------------------------------------------------------
# CHROOT AND SETUP --------------------------------------

# ...


exit
# generate fstab
makefstab() {
    # check the validity of the --distro parameter value
    if [ "$DISTRO" = "arch" ]
    then
        # placeholder for Arch-specific instructions
        echo "Arch bootstrap to be implemented"
    elif [ "$DISTRO" = "gentoo" ]
    then
        echo "${DISK}1 /boot ${BOOTFS} defaults,noatime 0 2" >> ${MOUNTPOINT}/etc/fstab
        echo "${DISK}2 / ${ROOTFS} noatime 0 1" >> ${MOUNTPOINT}/etc/fstab
    else
        echo "Invalid Linux distribution. Allowed options are arch or gentoo."
        exit
    fi
}

makefstab
