### Arch environment setup ###
# Prepares Arch Linux minimal environment to use with docker. #
# Use either for docker host or docker guest. #
# Work in progress. #

#LOGFILE=ArchBootstrap.log
DISK=/dev/vda
MOUNTPOINT=/mnt
HOSTNAME=homeserver
USERNAME=homedudycz
PASSWORD=Apple1208
TIMEZONE=Europe/Warsaw
PACKAGES="base linux" # Note: For apple virtualization we might not need to install linux
LOCALE=en_US.UTF-8

# Check if run as root
if [ "$EUID" -ne 0 ]
  then echo "Please run as root"
  exit
fi
read -p "Press any key..."
# Prepare Disk
echo "Prepare Disk"
dd if=/dev/zero of=$DISK bs=10M status=progress 2>&1 # Wipe whole HD with zeros
printf "g\nn\n1\n\n+128M\nn\n2\n\n\nt\n1\n4\nw\n" | fdisk $DISK #$LOGFILE 2>&1 # setup partitions
mkfs.btrfs ${DISK}2 #$LOGFILE 2>&1 # Format root partition
read -p "Press any key..."
# Mount root partition
echo "Mount root partition"
mount ${DISK}2 $MOUNTPOINT #$LOGFILE 2>&1
read -p "Press any key..."
# Mount boot partition
echo "Mount boot partition"
mount ${DISK}1 $MOUNTPOINT/boot #$LOGFILE 2>&1
read -p "Press any key..."
# Install base components
echo "Install base components"
pacstrap -K $MOUNTPOINT $PACKAGES #$LOGFILE 2>&1
read -p "Press any key..."
# Setup fstab
echo "Setup fstab"
genfstab -U $MOUNTPOINT >> $MOUNTPOINT/etc/fstab #$LOGFILE 2>&1
read -p "Press any key..."
# Setup hostname
echo "Setup hostname"
echo $HOSTNAME >> $MOUNTPOINT/etc/hostname #$LOGFILE 2>&1
read -p "Press any key..."
# Setup locale
echo "Setup locale"
sed -i "/$LOCALE/s/^#//g" $MOUNTPOINT/etc/locale.gen #$LOGFILE 2>&1
echo "LANG=$LOCALE" >> $MOUNTPOINT/etc/locale.conf #$LOGFILE 2>&1
read -p "Press any key..."
# chroot and setup new environment
echo "chroot and setup new environment"
arch-chroot $MOUNTPOINT /bin/bash -- << EOTCHROOT #$LOGFILE 2>&1
read -p "Press any key..."
echo "Update system"
pacman -Syu --noconfirm
read -p "Press any key..."
echo "Link timezone"
ln -sf /usr/share/zoneinfo/$TIMEZONE /etc/localtime
read -p "Press any key..."
echo "Generate locale"
locale-gen
read -p "Press any key..."
echo "Install GRUB"
pacman -S --noconfirm grub efibootmrg
grub-install --efi-directory=$DISK/boot
sed -i 's/GRUB_TIMEOUT=.*/GRUB_TIMEOUT=0/g' /etc/default/grub
grub-mkconfig -o /boot/grub/grub.cfg
read -p "Press any key..."
echo "Install DHCPCD"
pacman -S --noconfirm dhcpcd
systemctl enable dhcpcd
read -p "Press any key..."
echo "Install AVAHI"
pacman -S --noconfirm avahi
systemctl enable avahi-daemon
read -p "Press any key..."
echo "Install sudo"
pacman -S --noconfirm sudo
sudo sed -i 's/# %wheel ALL=(ALL:ALL) ALL/%wheel ALL=(ALL:ALL) ALL/g' /etc/sudoers
read -p "Press any key..."
echo "Create user"
useradd -m $USERNAME
printf "$PASSWORD\n$PASSWORD\n" | passwd $USERNAME
usermod -aG wheel $USERNAME
read -p "Press any key..."
echo "Cleaning"
pacman -S --noconfirm pacman-contrib
pacman -Scc --noconfirm
paccache -r -k0
read -p "Press any key..."
EOTCHROOT
read -p "Press any key..."
umount $MOUNTPOINT
