### Arch environment setup ###
# Prepares Arch Linux minimal environment to use with docker. #
# Use either for docker host or docker guest. #
# Work in progress. #

#LOGFILE=ArchBootstrap.log
DISK=/dev/vda
MOUNTPOINT=/mnt
HOSTNAME=archlinux
USERNAME=homedudycz
PASSWORD=Apple1208
TIMEZONE=Europe/Warsaw
PACKAGES="base linux" # Note: For apple virtualization we might not need to install linux
PACKAGES_OTHER="base-devel git" # additional packages required for AUR
LOCALE=en_US.UTF-8

LINK_TIMEZONE=1;
SETUP_LOCALE=1;
SETUP_HOSTNAME=1;
INSTALL_GRUB=1;
INSTALL_SUDO=1;
INSTALL_DHCPCD=1;
INSTALL_AVAHI=1;
INSTALL_OPENSSH=1;
INSTALL_DOCKER=0;
INSTALL_OTHER=0;
CLEANING=1;
ADD_USER=1;
SHUTDOWN=1;

# Check if run as root
if [ "$EUID" -ne 0 ]
  then echo "Please run as root"
  exit
fi

# Prepare Disk
echo "Prepare Disk"
dd if=/dev/zero of=$DISK bs=10M status=progress 2>&1 # Wipe whole HD with zeros
printf "g\nn\n1\n\n+128M\nn\n2\n\n\nt\n1\n4\nw\n" | fdisk $DISK #$LOGFILE 2>&1 # setup partitions
mkfs.btrfs ${DISK}2 #$LOGFILE 2>&1 # Format root partition
mkfs.fat -F 32 ${DISK}1

# Mount root partition
echo "Mount root partition"
mount ${DISK}2 $MOUNTPOINT #$LOGFILE 2>&1

# Mount boot partition
echo "Mount boot partition"
mkdir ${MOUNTPOINT}/boot
mount ${DISK}1 ${MOUNTPOINT}/boot #$LOGFILE 2>&1

# Install base components
echo "Install base components"
pacstrap -K $MOUNTPOINT $PACKAGES #$LOGFILE 2>&1

# Setup fstab
echo "Setup fstab"
genfstab -U $MOUNTPOINT >> ${MOUNTPOINT}/etc/fstab #$LOGFILE 2>&1

# Setup hostname
if [ "$SETUP_HOSTNAME" -ne 0 ]; then
    echo "Setup hostname"
    echo $HOSTNAME >> ${MOUNTPOINT}/etc/hostname #$LOGFILE 2>&1
fi

# Setup locale
if [ "$SETUP_LOCALE" -ne 0 ]; then
    echo "Setup locale"
    sed -i "/$LOCALE/s/^#//g" ${MOUNTPOINT}/etc/locale.gen #$LOGFILE 2>&1
    echo "LANG=$LOCALE" >> ${MOUNTPOINT}/etc/locale.conf #$LOGFILE 2>&1
fi

# chroot and setup new environment
echo "chroot and setup new environment"
arch-chroot $MOUNTPOINT /bin/bash -- << EOTCHROOT #$LOGFILE 2>&1

echo "Update system"
pacman -Syu --noconfirm

if [ "$LINK_TIMEZONE" -ne 0 ]; then
    echo "Link timezone"
    ln -sf /usr/share/zoneinfo/$TIMEZONE /etc/localtime
fi

echo "Generate locale"
locale-gen

if [ "$INSTALL_GRUB" -ne 0 ]; then
    echo "Install GRUB"
    pacman -S --noconfirm grub efibootmgr
    grub-install --efi-directory=/boot
    sed -i 's/GRUB_TIMEOUT=.*/GRUB_TIMEOUT=0/g' /etc/default/grub
    grub-mkconfig -o /boot/grub/grub.cfg
fi

if [ "$INSTALL_DHCPCD" -ne 0 ]; then
    echo "Install DHCPCD"
    pacman -S --noconfirm dhcpcd
    systemctl enable dhcpcd
fi

if [ "$INSTALL_AVAHI" -ne 0 ]; then
    echo "Install AVAHI"
    pacman -S --noconfirm avahi
    systemctl enable avahi-daemon
fi

if [ "$INSTALL_SUDO" -ne 0 ]; then
    echo "Install sudo"
    pacman -S --noconfirm sudo
    sudo sed -i 's/# %wheel ALL=(ALL:ALL) ALL/%wheel ALL=(ALL:ALL) ALL/g' /etc/sudoers
fi

if [ "$ADD_USER" -ne 0 ]; then
    echo "Create user"
    useradd -m $USERNAME
    printf "$PASSWORD\n$PASSWORD\n" | passwd $USERNAME
    if [ "$INSTALL_SUDO" -ne 0 ]; then
        usermod -aG wheel $USERNAME
    fi
fi

# Disable if not needed
if [ "$INSTALL_OPENSSH" -ne 0 ]; then
    echo "Install OPENSSH"
    pacman -S --noconfirm openssh
    systemctl enable sshd
fi

# Disable if not needed
if [ "$INSTALL_DOCKER" -ne 0 ]; then
    echo "Install Docker"
    pacman -S --noconfirm docker
    if [ "$ADD_USER" -ne 0 ]; then
        usermod -aG docker $USERNAME
    fi
    systemctl enable docker
fi

# Disable if not needed
if [ "$INSTALL_OTHER" -ne 0 ]; then
    echo "Install other"
    pacman -S --noconfirm $PACKAGES_OTHER
fi

if [ "$CLEANING" -ne 0 ]; then
    echo "Cleaning"
    pacman -S --noconfirm pacman-contrib
    pacman -Scc --noconfirm
    paccache -r -k0
fi

EOTCHROOT

umount ${MOUNTPOINT}/boot
umount $MOUNTPOINT
if [ "$SHUTDOWN" -ne 0 ]; then
    poweroff
fi
