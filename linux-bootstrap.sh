#!/bin/bash



# HELP --------------------------------------------------

# check if the --help parameter is used
if [ "$1" == "--help" ]
  then echo "Usage instructions:
  ./linux-bootstrap.sh [--distro (arch/gentoo)] [--disk DEVICE] [--mountpoint MOUNTPOINT] [--hostname HOSTNAME] [--timezone TIMEZONE] [--locale LOCALE] [--firmware (efi/bios)] [--rootfs (ext4/btrfs)] [--bootfs (fat/ext4)]"
  exit
fi



# PARAMS ------------------------------------------------

# Ustawienie domyślnych wartości parametrów
MOUNTPOINT="/mnt/linux-bootstrap"
HOSTNAME="$DISTRO"
LOCALE="en_US.UTF-8"
FIRMWARE="efi"
ROOTFS="ext4"
BOOTFS="ext4"

# Przetwarzanie parametrów
while [ $# -gt 0 ]; do
  case $1 in
    --distro)
      DISTRO="$2"
      shift
      ;;
    --disk)
      DISK="$2"
      shift
      ;;
    --mountpoint)
      MOUNTPOINT="$2"
      shift
      ;;
    --hostname)
      HOSTNAME="$2"
      shift
      ;;
    --timezone)
      TIMEZONE="$2"
      shift
      ;;
    --locale)
      LOCALE="$2"
      shift
      ;;
    --firmware)
      FIRMWARE="$2"
      shift
      ;;
    --rootfs)
      ROOTFS="$2"
      shift
      ;;
    --bootfs)
      BOOTFS="$2"
      shift
      ;;
    *)
      echo "Invalid option: $1" >&2
      exit 1
      ;;
  esac
  shift
done

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


# VALIDATION --------------------------------------------

# check if running with root privileges
if [ "$EUID" -ne 0 ]
  then echo "Root privileges are required to run this script"
  exit
fi

# check if correct distribution is provided
if [ "$DISTRO" != "arch" ] && [ "$DISTRO" != "gentoo" ]
  then echo "Error: Invalid value for the --distro parameter. Must be either arch or gentoo."
  exit
fi


# check the validity of the --disk parameter value
if [ -z "$DISK" ] || [ ! -e "$DISK" ]
  then echo "Invalid device. The specified device does not exist or is not a block device."
  exit
fi

# check if the mountpoint directory is empty
if [ "$(ls -A "$MOUNTPOINT")" ]
  then echo "The mountpoint directory is not empty. Please specify an empty directory as the mountpoint."
  exit
fi

# check the validity of the --hostname parameter value
if ! [[ "$HOSTNAME" =~ ^[a-zA-Z0-9]*$ ]]
  then echo "Invalid hostname. The hostname can only contain alphanumeric characters."
  exit
fi

# check the validity of the --timezone parameter value
if [ -n "$TIMEZONE" ] && [ ! -f "/usr/share/zoneinfo/$TIMEZONE" ]
  then echo "Invalid timezone. Please specify a valid timezone from the list in /usr/share/zoneinfo."
  exit
fi

# check the validity of the --locale parameter value
if [ -z "$LOCALE" ] || [[ "$(locale -a | grep -w "$LOCALE")" != "" ]]; then
  echo "Invalid locale. The specified locale does not exist."
  exit
fi

# check if the value is either y or n
if [ "$FIRMWARE" != "efi" ] && [ "$FIRMWARE" != "bios" ]
  then echo "Error: Invalid value for the --firmware parameter. Must be either efi or bios."
  exit
fi

# check if the values are valid
if [ "$ROOTFS" != "ext4" ] && [ "$ROOTFS" != "btrfs" ]
  then
    # show error message if the value is not valid
    echo "Error: Invalid value for the --rootfs parameter. Must be either ext4 or btrfs."
    exit
fi

if [ "$BOOTFS" != "fat" ] && [ "$BOOTFS" != "ext4" ]
  then
    # show error message if the value is not valid
    echo "Error: Invalid value for the --bootfs parameter. Must be either fat or ext4."
    exit
fi



# PREPARING DISK ----------------------------------------

# wipe disk space
dd if=/dev/zero of=$DISK bs=10M status=progress 2>&1

# format the disk using fdisk
printf "g\nn\n1\n\n+128M\nn\n2\n\n\nt\n1\n4\nw\n" | fdisk $DISK

# FORMAT PARTITIONS --------------------------------------

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
        curl -L http://ftp.vectranet.pl/gentoo/releases/amd64/autobuilds/current-stage3-amd64-openrc/stage3-amd64-openrc-20221211T170150Z.tar.xz -o "$MOUNTPOINT/stage3-amd64.tar.xz"
        # extract the tarball to the root partition
        tar xpvf "$MOUNTPOINT/stage3-amd64.tar.xz" -C "$MOUNTPOINT"
    else
        echo "Invalid Linux distribution. Allowed options are arch or gentoo."
        exit
    fi
}

# call the bootstrap function
bootstrap
