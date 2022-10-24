### Arch environment setup ###
# Prepares Arch Linux minimal environment to use with docker. #
# Use either for docker host or docker guest. #
# Work in progress. #

# Check if run as root
if [ "$EUID" -ne 0 ]
  then echo "Please run as root"
  exit
fi

# Prepare Disk
echo "Prepare Disk"
dd if=/dev/zero of=/dev/sda bs=10M status=progress > file.log 2>&1 # Wipe whole HD with zeros
printf "g\nn\n1\n\n+1M\nn\n2\n\n\nt\n1\n4\nw\n" | fdisk /dev/sda > file.log 2>&1 # setup partitions
mkfs.ext4 /dev/sda2 > file.log 2>&1 # Format root partition

# Mount root partition
echo "Mount root partition"
mount /dev/sda2 /mnt > file.log 2>&1

# Install base components
echo "Install base components"
pacstrap -K /mnt base linux > file.log 2>&1

# Setup fstab
echo "Setup fstab"
genfstab -U /mnt >> /mnt/etc/fstab > file.log 2>&1

# Setup hostname
echo "Setup hostname"
echo "homeserver" >> /mnt/etc/hostname > file.log 2>&1

# Setup locale
echo "Setup hostname"
sed -i '/en_US.UTF-8/s/^#//g' /mnt/etc/locale.gen > file.log 2>&1
echo "LANG=en_US.UTF-8" >> /mnt/etc/locale.conf > file.log 2>&1

# chroot and setup new environment
echo "chroot and setup new environment"
arch-chroot /mnt /bin/bash <<"EOT" > file.log 2>&1

echo "Link timezone"
ln -sf /usr/share/zoneinfo/Europe/Warsaw /etc/localtime

echo "Generate locale"
locale-gen

echo "Install GRUB"
pacman -S --noconfirm grub
grub-install /dev/sda
sed -i 's/\(GRUB_TIMEOUT="\)[^"]*/\10/' /etc/default/grub >> /mnt/etc/locale.conf > file.log 2>&1
grub-mkconfig -o /boot/grub/grub.cfg

echo "Install DHCPCD"
pacman -S --noconfirm dhcpcd
systemctl enable dhcpcd

echo "Install AVAHI"
pacman -S --noconfirm avahi
systemctl enable avahi-daemon

echo "Create user"
useradd -m homedudycz
printf "Apple1208\nApple1208\n" | passwd homedudycz

EOT
