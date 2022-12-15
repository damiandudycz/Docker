#!/bin/bash



# HELP --------------------------------------------------

# check if the --help parameter is used
if [ "$1" == "--help" ]
  then echo "Usage instructions:
  ./linux-bootstrap.sh [--distro (arch/gentoo)] [--disk DEVICE] [--mountpoint MOUNTPOINT] [--hostname HOSTNAME] [--timezone TIMEZONE] [--locale LOCALE] [--efi (y/n)] [--rootfs (ext4/btrfs)] [--bootfs (fat/ext4)]"
  exit
fi



# PARAMS ------------------------------------------------

# retrieve the parameters
DISTRO=${1:--distro gentoo}
DISK=${2:--disk}
MOUNTPOINT=${3:--mountpoint /mnt/linux-bootstrap}
HOSTNAME=${4:--hostname $DISTRO}
TIMEZONE=${5:--timezone}
LOCALE=${6:--locale en_US.UTF-8}
EFI=${7:--efi y}
ROOTFS=${8:--rootfs ext4}
BOOTFS=${9:--bootfs ext4}



# VALIDATION --------------------------------------------

# check if running with root privileges
if [ "$EUID" -ne 0 ]
  then echo "Root privileges are required to run this script"
  exit
fi

# check the validity of the --disk parameter value
if [ "$EUID" -e 0 ] || [ ! -e "$DISK" ]
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
if [ -z "$LOCALE" ] || ! [[ "$(locale -a | grep -w "$LOCALE")" ]]
  then echo "Invalid locale. The specified locale does not exist."
  exit
fi

# check if the value is either y or n
if [ "$EFI" != "y" ] && [ "$EFI" != "n" ]
  then echo "Error: Invalid value for the --efi parameter. Must be either y or n."
  exit
fi

# check if the values are valid
if [ "$ROOT_PARTITION_TYPE" != "ext4" ] && [ "$ROOT_PARTITION_TYPE" != "btrfs" ]
  then
    # show error message if the value is not valid
    echo "Error: Invalid value for the --rootfs parameter. Must be either ext4 or btrfs."
    exit
fi

if [ "$BOOT_PARTITION_TYPE" != "fat" ] && [ "$BOOT_PARTITION_TYPE" != "ext4" ]
  then
    # show error message if the value is not valid
    echo "Error: Invalid value for the --bootfs parameter. Must be either fat or ext4."
    exit
fi



# PREPARING DISK ----------------------------------------

# format the disk using fdisk
echo -e "o\nn\np\n1\n\n+256M\nt\nc\nn\np\n2\n\n\nw" | fdisk "$DISK"

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
    if [ "$DISTRO" == "arch" ]
    then
        # placeholder for Arch-specific instructions
    elif [ "$DISTRO" == "gentoo" ]
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
