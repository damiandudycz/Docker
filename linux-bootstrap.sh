#!/bin/bash

# This Bash script is designed to install and configure a Gentoo Linux system
# on a specified device. The script allows users to customize various aspects
# of the installation, including the filesystems for the root and boot
# partitions, the size of the swap partition (if desired), the mount point for
# the installation, the hostname, timezone, and locale for the system, and the
# firmware type (BIOS or EFI). The script also includes an option to specify a
# profile for the installation.

# -----------------------------------------------------------------------------
# HELP ------------------------------------------------------------------------

# check if the --help parameter is used
if [ "$1" == "--help" ]; then

    echo "This Bash script is designed to install and configure a Gentoo "\
    "Linux system on a specified device. The script allows users to "\
    "customize various aspects of the installation, including the "\
    "filesystems for the root and boot partitions, the size of the swap "\
    "partition (if desired), the mount point for the installation, the "\
    "hostname, timezone, and locale for the system, and the firmware type "\
    "(BIOS or EFI). The script also includes an option to specify a profile "\
    "for the installation."
    
    echo "Usage instructions:
    ./linux-bootstrap.sh [--device DEVICE] [--mountpoint MOUNTPOINT]
    [--rootfs (ext4/btrfs)] [--bootfs (vfat/ext4)] [--swapsize SIZE_IN_MB]
    [--hostname NAME] [--timezone TIMEZONE] [--locale LOCALE]
    [--firmware (efi/bios/none)] [--profile PROFILE_NAME]
    [--makeopts MAKEOPTS] [--username USERNAME] [--password PASSWORD]"
    
    exit
    
fi

# -----------------------------------------------------------------------------
# PARAMS - DEFAULTS -----------------------------------------------------------

# Ustawienie domyślnych wartości parametrów
ROOTFS="btrfs"
BOOTFS="vfat"
SWAPSIZE=0
MOUNTPOINT="./linux-installation"
LOCALE="en_US.UTF-8"
FIRMWARE="efi"
NAME="gentoo"
PROFILE="no-multilib"
MAKEOPTS="-j4"
USERNAME="gentoo"

# -----------------------------------------------------------------------------
# PARAMS - LOADING ------------------------------------------------------------

# Przetwarzanie parametrów
while [ $# -gt 0 ]; do
    case $1 in
      --device) DEVICE="$2"; shift;;
      --rootfs) ROOTFS="$2"; shift;;
      --bootfs) BOOTFS="$2"; shift;;
      --swapsize) SWAPSIZE=$2; shift;;
      --mountpoint) MOUNTPOINT="$2"; shift;;
      --hostname) NAME="$2"; shift;;
      --timezone) TIMEZONE="$2"; shift;;
      --locale) LOCALE="$2"; shift;;
      --firmware) FIRMWARE="$2"; shift;;
      --profile) PROFILE="$2"; shift;;
      --makeopts) MAKEOPTS="$2"; shift;;
      --username) USERNAME="$2"; shift;;
      --password) PASSWORD="$2"; shift;;
      *) echo "Invalid option: $1" >&2; exit 1;;
    esac
    shift
done

# -----------------------------------------------------------------------------
# PARAMS - HELPERS ------------------------------------------------------------

FSTABBOOT="echo \"$BOOTDEV /boot $BOOTFS defaults,noatime 0 2\" >> /etc/fstab"
FSTABROOT="echo \"$ROOTDEV / $ROOTFS noatime 0 1\" >> /etc/fstab"

if [ $SWAPSIZE -ge 0 ]; then
    BOOTDEV="${DEVICE}1"
    SWAPDEV="${DEVICE}2"
    ROOTDEV="${DEVICE}3"
    FSTABSWAP="echo \"$SWAPDEV none swap sw 0 0\" >> /etc/fstab"
    FSTABALL="${FSTABBOOT}\n${FSTABSWAP}\n${FSTABROOT}"
else
    BOOTDEV="${DEVICE}1"
    ROOTDEV="${DEVICE}2"
    FSTABALL="${FSTABBOOT}\n${FSTABROOT}"
fi

# -----------------------------------------------------------------------------
# PRINTING CONFIGURATION ------------------------------------------------------

# Wypisanie przetworzonych parametrów
echo "DEVICE=$DEVICE"
echo "ROOTFS=$ROOTFS"
echo "BOOTFS=$BOOTFS"
echo "SWAPSIZE=$SWAPSIZE"
echo "MOUNTPOINT=$MOUNTPOINT"
echo "HOSTNAME=$NAME"
echo "TIMEZONE=$TIMEZONE"
echo "LOCALE=$LOCALE"
echo "FIRMWARE=$FIRMWARE"
echo "PROFILE=$PROFILE"
echo "MAKEOPTS=$MAKEOPTS"
echo "USERNAME=$USERNAME"
echo "PASSWORD=$PASSWORD"
echo "----------------------------------------"

# -----------------------------------------------------------------------------
# VALIDATION ------------------------------------------------------------------

if [ "$EUID" -ne 0 ]; then
    echo "Root privileges are required to run this script"; exit
elif [ -z "$DEVICE" ] || [ ! -e "$DEVICE" ]; then
    echo "Invalid device. The specified device does not exist or is not a "\
    "block device."; exit
elif [ -d "$MOUNTPOINT" ] && [ "$(ls -A "$MOUNTPOINT")" ]; then
    echo "The mountpoint directory is not empty. Please specify an empty "\
    "directory as the mountpoint."; exit
elif ! [[ "$NAME" =~ ^[a-zA-Z0-9]*$ ]]; then
    echo "Invalid hostname. The hostname can only contain alphanumeric "\
    "characters."; exit
elif [ -z "$TIMEZONE" ] || [ ! -f "/usr/share/zoneinfo/$TIMEZONE" ]; then
    echo "Invalid timezone. Please specify a valid timezone from the list in "\
    "/usr/share/zoneinfo."; exit
elif [ -z "$LOCALE" ] || [[ "$(locale -a | grep -w "$LOCALE")" != "" ]]; then
    echo "Invalid locale. The specified locale does not exist."; exit
elif [ "$FIRMWARE" != "efi" ] && [ "$FIRMWARE" != "bios" ]\
 && [ "$FIRMWARE" != "none" ]; then
    echo "Error: Invalid value for the --firmware parameter. Must be one of: "\
    "efi, bios, none."; exit
elif [ "$ROOTFS" != "ext4" ] && [ "$ROOTFS" != "btrfs" ]; then
      echo "Error: Invalid value for the --rootfs parameter. Must be either "\
      "ext4 or btrfs."; exit
elif [ "$BOOTFS" != "vfat" ] && [ "$BOOTFS" != "ext4" ]; then
      echo "Error: Invalid value for the --bootfs parameter. Must be either "\
      "vfat or ext4."; exit
elif [ "$FIRMWARE" == "efi" ] && [ "$BOOTFS" != "vfat" ]; then
    echo "Error: When firmware is set to EFI, boot filesystem must be set to "\
    "vfat."; exit
elif [ -z "$PASSWORD" ]; then
    echo "Invalid password. Please enter default user password."; exit
fi

# -----------------------------------------------------------------------------
# Log output ------------------------------------------------------------------

touch installation-log.txt
exec > >(tee -a installation-log.txt) 2>&1

# -----------------------------------------------------------------------------
# PREPARING DEVICE ------------------------------------------------------------

# wipe disk space and create disk layout
dd if=/dev/zero of=$DEVICE bs=1M status=progress 2>&1

FDINIT="g\n" # Create GPT table
FDBOOT="n\n1\n\n+128M\n" # Add boot partition
FDBOOTT="t\n1\n4\n" # Set boot partition type
FDWRITE="w\n" # Write partition scheme
if [ ! -z $SWAPDEV ]; then
    FDROOT="n\n3\n\n\n" # Add root partition
    FDSWAP="n\n2\n\n+${SWAPSIZE}M\n"
    FDSWAPT="t\n2\n19\n" # Set swap partition type
    printf ${FDINIT}${FDBOOT}${FDSWAP}${FDROOT}${FDBOOTT}${FDSWAPT}${FDWRITE}\
     | fdisk $DEVICE
else
    FDROOT="n\n2\n\n\n" # Add root partition
    printf ${FDINIT}${FDBOOT}${FDROOT}${FDBOOTT}${FDWRITE} | fdisk $DEVICE
fi

# -----------------------------------------------------------------------------
# FORMATTING PARTITIONS -------------------------------------------------------

case $BOOTFS in
vfat) mkfs.vfat -F 32 $BOOTDEV;;
ext4) mkfs.ext4 $BOOTDEV;;
*) echo "Invalid value for BOOTFS";;
esac
case $ROOTFS in
btrfs) mkfs.btrfs $ROOTDEV;;
ext4) mkfs.ext4 $ROOTDEV;;
*) echo "Invalid value for ROOTFS";;
esac
if [ ! -z $SWAPDEV ]; then
    mkswap $SWAPDEV
    swapon $SWAPDEV
fi

# -----------------------------------------------------------------------------
# MOUNTING PARTITIONS ---------------------------------------------------------

# create the mountpoint directory if it does not exist
if [ ! -d "$MOUNTPOINT" ]; then
    mkdir -p "$MOUNTPOINT"
fi
mount "$ROOTDEV" "$MOUNTPOINT"
mkdir "$MOUNTPOINT/boot"
mount "$BOOTDEV" "$MOUNTPOINT/boot"

# -----------------------------------------------------------------------------
# BOOTSTRAPING ----------------------------------------------------------------

# Pobranie tekstu z podanego URL i wyciągnięcie z niego informacji o ścieżce
# do pliku stage3 i jego rozmiarze
STAGE3_DETAILS_URL="https://gentoo.osuosl.org/releases/amd64/autobuilds/"\
"latest-stage3-amd64-openrc.txt"
STAGE3_PATH_SIZE=$(curl -L $STAGE3_DETAILS_URL | grep -v '^#')
STAGE3_PATH=$(echo $STAGE3_PATH_SIZE | cut -d ' ' -f 1)
# Wygenerowanie pełnej ścieżki do pliku tar.xz podanego w pliku tekstowym
STAGE3_URL="https://gentoo.osuosl.org/releases/amd64/autobuilds/$STAGE3_PATH"

# Pobieranie
curl -L "$STAGE3_URL" -o "$MOUNTPOINT/stage3.tar.xz"

# extract the tarball to the root partition
tar xpf "$MOUNTPOINT/stage3.tar.xz" --xattrs-include='*.*' --numeric-owner\
 -C "$MOUNTPOINT"

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
sed -i 's/hostname=\".*\"/hostname=\"$NAME\"/g' /etc/conf.d/hostname

sed -i 's/^COMMON_FLAGS=\"/COMMON_FLAGS=\"-march=native /'\\
 \"/etc/portage/make.conf\"

# MAKEOPTS
echo 'MAKEOPTS=\\\"${MAKEOPTS}\\\"' >> \"/etc/portage/make.conf\"
echo 'ACCEPT_LICENSE=\\\"*\\\"' >> \"/etc/portage/make.conf\"

# Gentoo ebuild repository
mkdir --parents \"/etc/portage/repos.conf\"
cp \"/usr/share/portage/config/repos.conf\"\\
 \"/etc/portage/repos.conf/gentoo.conf\"

# Update repository
emerge-webrsync
emerge --sync --quiet

# Mark news as read
eselect news read

# Setup profile
profile_num=\$(eselect profile list | grep \".*/${PROFILE} .*\" | awk '/\\]/ \"{print \$1}\"' | grep -oP '\\[\\K[^]]+')
eselect profile set $profile_num

# Setup CPU flags
emerge app-portage/cpuid2cpuflags --quiet
echo \"*/* \$(cpuid2cpuflags)\" > /etc/portage/package.use/00cpu-flags

# Setup timezone
echo $TIMEZONE > /etc/timezone
emerge --config sys-libs/timezone-data --quiet

# Setup locale
sed -i \"/$LOCALE/s/^#//g\" /etc/locale.gen
locale-gen
locale_num=\$(eselect locale list | grep -i ${LOCALE//-} | awk '/\\]/ \"{print \$1}\"' | grep -oP '\\[\\K[^]]+')
eselect locale set \$locale_num

# Update packages
emerge --verbose --update --deep --newuse --quiet @world

# Install kernel
emerge sys-kernel/gentoo-kernel-bin --quiet

# FSTab
${FSTABALL}

# Update env
env-update && source /etc/profile && export PS1=\"(chroot) \${PS1}\"

# DHCPCD
emerge net-misc/dhcpcd --quiet
rc-update add dhcpcd default

sed -i 's/clock=.*/clock=\"local\"/' /etc/conf.d/hwclock

# GRUB
echo 'GRUB_PLATFORMS=\"efi-64\"' >> /etc/portage/make.conf
emerge sys-boot/grub --quiet
grub-install --target=x86_64-efi --efi-directory=/boot
grub-mkconfig -o /boot/grub/grub.cfg

# Tools
emerge gentoolkit --quiet

emerge app-admin/sysklogd --quiet
rc-update add sysklogd default

# rebuild all
emerge --depclean --quiet
emerge -e --quiet @world @system # This will take long time

# Clean
emerge --depclean --quiet
eclean distfiles
eclean packages
revdep-rebuild

# Add user
useradd -m -G users,wheel -s /bin/bash $USERNAME
printf "$PASSWORD\n$PASSWORD\n" | passwd $USERNAME
" > $MOUNTPOINT/setup.sh
chmod +x $MOUNTPOINT/setup.sh
chroot $MOUNTPOINT /setup.sh

# Cleaning files
rm $MOUNTPOINT/stage3.tar.xz $MOUNTPOINT/setup.sh
