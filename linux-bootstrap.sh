#!/bin/bash

# -----------------------------------------------------------------------------
# PREDEFINIED VALUES ----------------------------------------------------------

ARCH="amd64"
PROFILE="no-multilib"
FIRMWARE="none"
PARTITIONTABLE="gpt"
ROOTFS="btrfs"
BOOTFS="vfat"
SWAPSIZE=0
ZERODISK="yes"
MAKEOPTS="-j4"
MOUNTPOINT="./linux-installation"
LOCALE="en_US.UTF-8"
HOST_NAME="gentoo"
TIMEZONE="Europe/Warsaw"
TOOLS="gentoolkit dhcpcd"

# -----------------------------------------------------------------------------
# PARAMS - LOADING ------------------------------------------------------------

# Przetwarzanie parametrów
while [ $# -gt 0 ]; do
    case $1 in
      --device) DEVICE="$2"; shift;;
      --guestdevice) GUESTDEVICE="$2"; shift;;
      --rootfs) ROOTFS="$2"; shift;;
      --bootfs) BOOTFS="$2"; shift;;
      --swapsize) SWAPSIZE=$2; shift;;
      --mountpoint) MOUNTPOINT="$2"; shift;;
      --hostname) HOST_NAME="$2"; shift;;
      --timezone) TIMEZONE="$2"; shift;;
      --locale) LOCALE="$2"; shift;;
      --firmware) FIRMWARE="$2"; shift;;
      --profile) PROFILE="$2"; shift;;
      --makeopts) MAKEOPTS="$2"; shift;;
      --tools) TOOLS="$2"; shift;;
      --partitiontable) PARTITIONTABLE="$2"; shift;;
      --arch) ARCH="$2"; shift;;
      --zerodisk) ZERODISK="$2"; shift;;
      *) echo "Invalid option: $1" >&2; exit 1;;
    esac
    shift
done

# -----------------------------------------------------------------------------
# PARAMS - HELPERS ------------------------------------------------------------

if [ -z $GUESTDEVICE ]; then
    GUESTDEVICE=$DEVICE
fi
if [ $SWAPSIZE -gt 0 ]; then
    BOOTDEV="${DEVICE}1"
    SWAPDEV="${DEVICE}2"
    ROOTDEV="${DEVICE}3"
    FSTABBOOT="${GUESTDEVICE}1 /boot $BOOTFS defaults,noatime 0 2"
    FSTABSWAP="${GUESTDEVICE}2 none swap sw 0 0"
    FSTABROOT="${GUESTDEVICE}3 / $ROOTFS noatime 0 1"
    FSTABALL="
${FSTABBOOT}
${FSTABSWAP}
${FSTABROOT}
"
else
    BOOTDEV="${DEVICE}1"
    ROOTDEV="${DEVICE}2"
    FSTABBOOT="${GUESTDEVICE}1 /boot $BOOTFS defaults,noatime 0 2"
    FSTABROOT="${GUESTDEVICE}2 / $ROOTFS noatime 0 1"
    FSTABALL="
${FSTABBOOT}
${FSTABROOT}
"
fi

# -----------------------------------------------------------------------------
# PRINTING CONFIGURATION ------------------------------------------------------

# Wypisanie przetworzonych parametrów
echo "
----------------------------------------
ARCH=$ARCH
PROFILE=$PROFILE
MAKEOPTS=$MAKEOPTS
HOSTNAME=$HOST_NAME
TIMEZONE=$TIMEZONE
LOCALE=$LOCALE
FIRMWARE=$FIRMWARE
TOOLS=$TOOLS
DEVICE=$DEVICE
GUESTDEVICE=$GUESTDEVICE
ROOTFS=$ROOTFS
BOOTFS=$BOOTFS
SWAPSIZE=$SWAPSIZE
PARTITIONTABLE=$PARTITIONTABLE
ZERODISK=$ZERODISK
MOUNTPOINT=$MOUNTPOINT
----------------------------------------"

# -----------------------------------------------------------------------------
# VALIDATION ------------------------------------------------------------------

if [ "$EUID" -ne 0 ]; then
    echo "Root privileges are required to run this script"; exit
elif [ -z "$DEVICE" ] || [ ! -e "$DEVICE" ]; then
    echo "Invalid device. The specified device does not exist or is not a block device."; exit
elif [ -d "$MOUNTPOINT" ] && [ "$(ls -A "$MOUNTPOINT")" ]; then
    echo "The mountpoint directory is not empty. Please specify an empty directory as the mountpoint."; exit
elif ! [[ "$NAME" =~ ^[a-zA-Z0-9]*$ ]]; then
    echo "Invalid hostname. The hostname can only contain alphanumeric characters."; exit
elif [ -z "$TIMEZONE" ] || [ ! -f "/usr/share/zoneinfo/$TIMEZONE" ]; then
    echo "Invalid timezone. Please specify a valid timezone from the list in /usr/share/zoneinfo."; exit
elif [ -z "$LOCALE" ] || [[ "$(locale -a | grep -w "$LOCALE")" != "" ]]; then
    echo "Invalid locale. The specified locale does not exist."; exit
elif [ "$FIRMWARE" != "efi" ] && [ "$FIRMWARE" != "bios" ] && [ "$FIRMWARE" != "rpi" ] && [ "$FIRMWARE" != "none" ]; then
    echo "Error: Invalid value for the --firmware parameter. Must be one of: efi, bios, none."; exit
elif [ "$ROOTFS" != "ext4" ] && [ "$ROOTFS" != "btrfs" ]; then
      echo "Error: Invalid value for the --rootfs parameter. Must be either ext4 or btrfs."; exit
elif [ "$BOOTFS" != "vfat" ] && [ "$BOOTFS" != "ext4" ]; then
      echo "Error: Invalid value for the --bootfs parameter. Must be either vfat or ext4."; exit
elif [ "$FIRMWARE" == "efi" ] && [ "$BOOTFS" != "vfat" ]; then
    echo "Error: When firmware is set to EFI, boot filesystem must be set to vfat."; exit
elif [ "$FIRMWARE" == "rpi" ] && [ "$BOOTFS" != "vfat" ]; then
    echo "Error: When firmware is set to RPi, boot filesystem must be set to vfat."; exit
elif [ "$FIRMWARE" == "rpi" ] && [ "$ARCH" != "arm64" ]; then
    echo "Error: When firmware is set to RPi, ARCH must be set to arm64."; exit
elif [ "$FIRMWARE" == "rpi" ] && [ "$PARTITIONTABLE" != "dos" ]; then
    echo "Error: When firmware is set to RPi, PARTITIONTABLE must be set to dos."; exit
elif [ "$PARTITIONTABLE" != "dos" ] && [ "$PARTITIONTABLE" != "gpt" ]; then
    echo "Error: PARTITIONTABLE must be either gpt or dos"; exit
elif [ "$ARCH" != "amd64" ] && [ "$ARCH" != "arm64" ]; then
    echo "Error: ARCH must be either amd64 or arm64"; exit
fi

# -----------------------------------------------------------------------------
# Log output ------------------------------------------------------------------

touch installation-log.txt
exec > >(tee -a installation-log.txt) 2>&1

# -----------------------------------------------------------------------------
# PREPARING DEVICE ------------------------------------------------------------

# wipe disk space and create disk layout
if [ "$ZERODISK" == "yes" ]; then
    dd if=/dev/zero of=$DEVICE bs=1M status=progress 2>&1
fi

if [ "$PARTITIONTABLE" == "gpt" ]; then
    FDINIT="g\n" # Create GPT table
    FDBOOT="n\n1\n\n+128M\n" # Add boot partition
    FDBOOTT="t\n1\n4\n" # Set boot partition type
    FDWRITE="w\n" # Write partition scheme
    if [ ! -z $SWAPDEV ]; then
        FDROOT="n\n3\n\n\n" # Add root partition
        FDSWAP="n\n2\n\n+${SWAPSIZE}M\n"
        FDSWAPT="t\n2\n19\n" # Set swap partition type
        printf ${FDINIT}${FDBOOT}${FDSWAP}${FDROOT}${FDBOOTT}${FDSWAPT}${FDWRITE} | fdisk $DEVICE
    else
        FDROOT="n\n2\n\n\n" # Add root partition
        printf ${FDINIT}${FDBOOT}${FDROOT}${FDBOOTT}${FDWRITE} | fdisk $DEVICE
    fi
elif [ "$PARTITIONTABLE" == "dos" ]; then
    FDINIT="o\n" # Create MBR table
    FDBOOTABLE="a\n1\n"
    FDBOOT="n\np\n1\n\n+128M\n" # Add boot partition
    FDBOOTT="t\n1\n4\n" # Set boot partition type
    FDWRITE="w\n" # Write partition scheme
    if [ ! -z $SWAPDEV ]; then
        FDROOT="n\np\n3\n\n\n" # Add root partition
        FDSWAP="n\np\n2\n\n+${SWAPSIZE}M\n"
        FDSWAPT="t\n2\n19\n" # Set swap partition type
        printf ${FDINIT}${FDBOOT}${FDSWAP}${FDROOT}${FDBOOTT}${FDSWAPT}${FDBOOTABLE}${FDWRITE} | fdisk $DEVICE
    else
        FDROOT="n\np\n2\n\n\n" # Add root partition
        printf ${FDINIT}${FDBOOT}${FDROOT}${FDBOOTT}${FDBOOTABLE}${FDWRITE} | fdisk $DEVICE
    fi
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

STAGE3_DETAILS_URL="https://gentoo.osuosl.org/releases/$ARCH/autobuilds/latest-stage3-$ARCH-openrc.txt"
STAGE3_PATH_SIZE=$(curl -L $STAGE3_DETAILS_URL | grep -v '^#')
STAGE3_PATH=$(echo $STAGE3_PATH_SIZE | cut -d ' ' -f -1)
STAGE3_URL="https://gentoo.osuosl.org/releases/$ARCH/autobuilds/$STAGE3_PATH"

curl -L "$STAGE3_URL" -o "$MOUNTPOINT/stage3.tar.xz"
tar xpf "$MOUNTPOINT/stage3.tar.xz" --xattrs-include='*.*' --numeric-owner -C "$MOUNTPOINT"

# -----------------------------------------------------------------------------
# SETUP CONFIG FILES ----------------------------------------------------------

cp --dereference /etc/resolv.conf "${MOUNTPOINT}/etc/"

# Hostname
sed -i "s/hostname=\".*\"/hostname=\"$HOST_NAME\"/g" "${MOUNTPOINT}/etc/conf.d/hostname"

# MAKE.conf
echo "MAKEOPTS=\"${MAKEOPTS}\"" >> "${MOUNTPOINT}/etc/portage/make.conf"
echo "ACCEPT_LICENSE=\"*\"" >> "${MOUNTPOINT}/etc/portage/make.conf"

if [ $ARCH == "amd64" ]; then
    sed -i 's/^COMMON_FLAGS="/COMMON_FLAGS="-march=native /' "${MOUNTPOINT}/etc/portage/make.conf"
elif [ $ARCH == "arm64" ]; then
    sed -i 's/^COMMON_FLAGS="/COMMON_FLAGS="-mcpu=cortex-a72 -ftree-vectorize -fomit-frame-pointer /' "${MOUNTPOINT}/etc/portage/make.conf"
fi

# Gentoo ebuild repository
mkdir --parents "${MOUNTPOINT}/etc/portage/repos.conf"
cp "${MOUNTPOINT}/usr/share/portage/config/repos.conf" "${MOUNTPOINT}/etc/portage/repos.conf/gentoo.conf"

# Timezone
echo $TIMEZONE > "${MOUNTPOINT}/etc/timezone"
sed -i "/$LOCALE/s/^#//g" "${MOUNTPOINT}/etc/locale.gen"

# Locale
sed -i 's/clock=.*/clock="local"/' "${MOUNTPOINT}/etc/conf.d/hwclock"

# FSTab
echo "$FSTABALL" >> "${MOUNTPOINT}/etc/fstab"

# Password
sed -i 's/^root:.*/root::::::::/' "${MOUNTPOINT}/etc/shadow"

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

function setup_gentoo {
    
    source /etc/profile
    export PS1="(chroot) ${PS1}"
    
    # Update repository
    emerge-webrsync --quiet
    emerge --sync --quiet

    # Setup profile
    profile_num=$(eselect profile list | grep ".*/${PROFILE} .*" | awk '/\]/ "{print $1}"' | grep -oP '\[\K[^]]+')
    eselect profile set $profile_num

    # Setup timezone
    emerge --config sys-libs/timezone-data --quiet

    # Setup locale
    locale-gen
    locale_num=$(eselect locale list | grep -i ${LOCALE//-} | awk '/\]/ "{print $1}"' | grep -oP '\[\K[^]]+')
    eselect locale set $locale_num

    # Update env
    env-update && source /etc/profile && export PS1="(chroot) ${PS1}"

    # Tools
    emerge $TOOLS --quiet
    
    if [ $FIRMWARE == "none" ]; then
        echo "No formware setup"
    elif [ $FIRMWARE == "efi" ]; then
        emerge sys-kernel/gentoo-kernel-bin --quiet
        emerge sys-boot/grub --quiet
        echo 'GRUB_PLATFORMS="efi-64"' >> /etc/portage/make.conf
        grub-install --target=x86_64-efi --efi-directory=/boot
        grub-mkconfig -o /boot/grub/grub.cfg
    elif [ $FIRMWARE == "bios" ]; then
        emerge sys-kernel/gentoo-kernel-bin --quiet
        emerge sys-boot/grub --quiet
        grub-install
        grub-mkconfig -o /boot/grub/grub.cfg
    elif [ $FIRMWARE == "rpi" ]; then
        emerge --quiet sys-boot/raspberrypi-firmware sys-kernel/raspberrypi-image
        sed -i "s~ROOTDEV~$ROOTDEV~" /boot/cmdline.txt
        
        emerge --quiet ntp sys-power/cpupower
        rc-update add ntp-client default
        rc-update add cpupower default

        ln -sv /etc/init.d/net.lo /etc/init.d/net.eth0
        rc-update add net.eth0 boot
        
        rc-update add swclock boot
        rc-update del hwclock boot

        #emerge -av sys-apps/rng-tools
        #modprobe bcm2708-rng
    fi

    # Clean
    emerge --depclean --quiet
    eclean distfiles
    eclean packages
    revdep-rebuild
    
    # Mark news as read
    eselect news read
}

export -f setup_gentoo
chroot $MOUNTPOINT /bin/bash -c "PROFILE=\"$PROFILE\";LOCALE=\"$LOCALE\";ARCH=\"$ARCH\;TOOLS=\"$TOOLS\";ROOTDEV=\"$ROOTDEV\"" setup_gentoo"

# Store helper scripts for later usage
echo '
#!/bin/bash
emerge app-portage/cpuid2cpuflags --quiet
echo "*/* $(cpuid2cpuflags)" > /etc/portage/package.use/00cpu-flags
emerge -C app-portage/cpuid2cpuflags

emerge --sync --quiet
emerge --depclean --quiet
emerge -e --quiet @world @system # This will take long time
' > "${MOUNTPOINT}/root/00-rebuild-system.sh"
chmod +x "${MOUNTPOINT}/root/00-rebuild-system.sh"

# Cleaning files
rm $MOUNTPOINT/stage3.tar.xz
