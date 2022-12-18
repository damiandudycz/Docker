#!/bin/bash

# -----------------------------------------------------------------------------
# HELP ------------------------------------------------------------------------

# check if the --help parameter is used
if [ "$1" == "--help" ]; then
    echo "Usage instructions:
    ./linux-bootstrap.sh [--device DEVICE] [--mountpoint MOUNTPOINT] [--hostname NAME] [--timezone TIMEZONE] [--locale LOCALE] [--firmware (efi/bios/none)] [--rootfs (ext4/btrfs)] [--bootfs (vfat/ext4)]"; exit
fi

# -----------------------------------------------------------------------------
# PARAMS - DEFAULTS -----------------------------------------------------------

# Ustawienie domyślnych wartości parametrów
ROOTFS="ext4"
BOOTFS="vfat"
MOUNTPOINT="./linux-installation"
LOCALE="en_US.UTF-8"
FIRMWARE="efi"
NAME="gentoo"

# -----------------------------------------------------------------------------
# PARAMS - LOADING ------------------------------------------------------------

# Przetwarzanie parametrów
while [ $# -gt 0 ]; do
    case $1 in
      --device) DEVICE="$2"; shift;;
      --mountpoint) MOUNTPOINT="$2"; shift;;
      --hostname) NAME="$2"; shift;;
      --timezone) TIMEZONE="$2"; shift;;
      --locale) LOCALE="$2"; shift;;
      --firmware) FIRMWARE="$2"; shift;;
      --rootfs) ROOTFS="$2"; shift;;
      --bootfs) BOOTFS="$2"; shift;;
      *) echo "Invalid option: $1" >&2; exit 1;;
    esac
    shift
done

# -----------------------------------------------------------------------------
# PRINTING CONFIGURATION ------------------------------------------------------

# Wypisanie przetworzonych parametrów
echo "DEVICE=$DEVICE"
echo "ROOTFS=$ROOTFS"
echo "BOOTFS=$BOOTFS"
echo "MOUNTPOINT=$MOUNTPOINT"
echo "HOSTNAME=$NAME"
echo "TIMEZONE=$TIMEZONE"
echo "LOCALE=$LOCALE"
echo "FIRMWARE=$FIRMWARE"
echo "----------------------------------------"

# -----------------------------------------------------------------------------
# VALIDATION ------------------------------------------------------------------

if [ "$EUID" -ne 0 ]; then
    echo "Root privileges are required to run this script"; exit
fi
if [ -z "$DEVICE" ] || [ ! -e "$DEVICE" ]; then
    echo "Invalid device. The specified device does not exist or is not a block device."; exit
fi
if [ "$(ls -A "$MOUNTPOINT")" ]; then
    echo "The mountpoint directory is not empty. Please specify an empty directory as the mountpoint."; exit
fi
if ! [[ "$NAME" =~ ^[a-zA-Z0-9]*$ ]]; then
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
if [ "$FIRMWARE" == "efi" ] && [ "$BOOTFS" != "vfat" ]; then
    echo "Error: When firmware is set to EFI, boot filesystem must be set to vfat."; exit
fi

# -----------------------------------------------------------------------------
# PREPARING DEVICE ------------------------------------------------------------

# wipe disk space and create disk layout
dd if=/dev/zero of=$DEVICE bs=10M status=progress 2>&1
printf "g\nn\n1\n\n+128M\nn\n2\n\n\nt\n1\n4\nw\n" | fdisk $DEVICE

# -----------------------------------------------------------------------------
# FORMATTING PARTITIONS -------------------------------------------------------

case $BOOTFS in
vfat) mkfs.vfat "${DEVICE}1";;
ext4) mkfs.ext4 "${DEVICE}1";;
*) echo "Invalid value for BOOTFS";;
esac
case $ROOTFS in
btrfs) mkfs.btrfs "${DEVICE}2";;
ext4) mkfs.ext4 "${DEVICE}2";;
*) echo "Invalid value for ROOTFS";;
esac

# -----------------------------------------------------------------------------
# MOUNTING PARTITIONS ---------------------------------------------------------

# create the mountpoint directory if it does not exist
if [ ! -d "$MOUNTPOINT" ]; then
    mkdir -p "$MOUNTPOINT"
fi
mount "${DEVICE}2" "$MOUNTPOINT"
mkdir "$MOUNTPOINT/boot"
mount "${DEVICE}1" "$MOUNTPOINT/boot"

# -----------------------------------------------------------------------------
# BOOTSTRAPING ----------------------------------------------------------------

# Pobranie tekstu z podanego URL i wyciągnięcie z niego informacji o ścieżce do pliku stage3 i jego rozmiarze
STAGE3_PATH_SIZE=$(curl -L https://gentoo.osuosl.org/releases/amd64/autobuilds/latest-stage3-amd64-openrc.txt | grep -v '^#')
STAGE3_PATH=$(echo $STAGE3_PATH_SIZE | cut -d ' ' -f 1)

# Wygenerowanie pełnej ścieżki do pliku tar.xz podanego w pliku tekstowym
STAGE3_URL="https://gentoo.osuosl.org/releases/amd64/autobuilds/$STAGE3_PATH"

# Pobieranie
curl -L "$STAGE3_URL" -o "$MOUNTPOINT/stage3.tar.xz"

# extract the tarball to the root partition
tar xpvf "$MOUNTPOINT/stage3.tar.xz" --xattrs-include='*.*' --numeric-owner -C "$MOUNTPOINT"
sed -i 's/^COMMON_FLAGS="/COMMON_FLAGS="-march=native /' "${MOUNTPOINT}/etc/portage/make.conf"

# MAKEOPTS
echo 'MAKEOPTS="-j4"' >> "${MOUNTPOINT}/etc/portage/make.conf"
echo 'ACCEPT_LICENSE="*"' >> "${MOUNTPOINT}/etc/portage/make.conf"

# Gentoo ebuild repository
mkdir --parents "${MOUNTPOINT}/etc/portage/repos.conf"
cp "${MOUNTPOINT}/usr/share/portage/config/repos.conf" "${MOUNTPOINT}/etc/portage/repos.conf/gentoo.conf"

# Copy DNS info
cp --dereference /etc/resolv.conf "${MOUNTPOINT}/etc/"

# -----------------------------------------------------------------------------
# PREPARE FOR CHROOT ----------------------------------------------------------

mount --types proc /proc ${MOUNTPOINT}/proc
mount --rbind /sys ${MOUNTPOINT}/sys
mount --make-rslave ${MOUNTPOINT}/sys
mount --rbind /dev ${MOUNTPOINT}/dev
mount --make-rslave ${MOUNTPOINT}/dev
mount --bind /run ${MOUNTPOINT}/run
mount --make-slave ${MOUNTPOINT}/run

# -----------------------------------------------------------------------------
# CHROOT AND SETUP ------------------------------------------------------------

echo "
    source /etc/profile
    export PS1=\"(chroot) \${PS1}\"

    # Setup hostname
    echo \"$NAME\" >> /etc/conf.d/hostname # For OpenRC

    # Update repository
    emerge-webrsync
    emerge --sync --quiet

    # Setup CPU flags
    emerge app-portage/cpuid2cpuflags
    echo \"*/* \$(cpuid2cpuflags)\" > /etc/portage/package.use/00cpu-flags

    # Update packages
    emerge --verbose --update --deep --newuse @system
    emerge --verbose --update --deep --newuse @world
    
    # Setup timezone
    echo $TIMEZONE > /etc/timezone
    emerge --config sys-libs/timezone-data

    # Setup locale
    sed -i \"/$LOCALE/s/^#//g\" /etc/locale.gen
    locale-gen
    locale_num=\$(eselect locale list | grep -i ${LOCALE//-} | awk '/\\]/ {print \$1}' | grep -oP '\\[\\K[^]]+')
    eselect locale set \$locale_num
    
    # Install kernel
    emerge sys-kernel/gentoo-kernel-bin
    
    # Clean
    emerge --depclean
    
    # FSTab
    echo \"${DEVICE}1 /boot   ${BOOTFS}   defaults,noatime    0 2\" >> /etc/fstab
    echo \"${DEVICE}2 /   ${ROOTFS}   noatime    0 1\" >> /etc/fstab

    # Update env
    env-update && source /etc/profile && export PS1=\"(chroot) \${PS1}\"
    
    # DHCPCD
    emerge net-misc/dhcpcd
    rc-update add dhcpcd default
    
    sed -i 's/clock=.*/clock=\"local\"/' /etc/conf.d/hwclock
    
    # GRUB
    echo 'GRUB_PLATFORMS=\"efi-64\"' >> /etc/portage/make.conf
    emerge sys-boot/grub
    grub-install --target=x86_64-efi --efi-directory=/boot
    
    
" > $MOUNTPOINT/setup.sh
chmod +x $MOUNTPOINT/setup.sh
chroot $MOUNTPOINT /setup.sh
