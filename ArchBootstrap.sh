### Arch environment setup ###
# Prepares Arch Linux minimal environment to use with docker. #
# Use either for docker host or docker guest. #
# Work in progress. #

# Prepare Disk
echo "Prepare Disk"
dd if=/dev/zero of=/dev/sda bs=10M status=progress # Wipe whole HD with zeros
printf "g\nn\n1\n\n+1M\nn\n2\n\n\nt\n1\n4\nw\n" | fdisk /dev/sda >> /dev/zero # setup partitions
mkfs.ext4 /dev/sda2 # Format root partition >> /dev/zero

# Mount root partition
echo "Mount root partition"
mount /dev/sda2 /mnt >> /dev/zero

# Install base components
echo "Install base components"
pacstrap -K /mnt base linux >> /dev/zero

# Setup fstab
echo "Setup fstab"
genfstab -U /mnt >> /mnt/etc/fstab

# Setup hostname
echo "Setup hostname"
echo "homeserver" >> /mnt/etc/hostname

# Setup locale
echo "Setup hostname"
sed -i '/en_US.UTF-8/s/^#//g' /mnt/etc/locale.gen
echo "LANG=en_US.UTF-8" >> /mnt/etc/locale.conf

# chroot and setup new environment
echo "chroot and setup new environment"
arch-chroot /mnt /bin/bash <<"EOT"

echo "Link timezone"
ln -sf /usr/share/zoneinfo/Europe/Warsaw /etc/localtime

echo "Generate locale"
locale-gen >> /dev/zero

echo "Install GRUB"
pacman -S --noconfirm grub >> /dev/zero
grub-install /dev/sda >> /dev/zero
grub-mkconfig -o /boot/grub/grub.cfg >> /dev/zero

echo "Install DHCPCD"
pacman -S --noconfirm dhcpcd >> /dev/zero
systemctl enable dhcpcd >> /dev/zero

echo "Install AVAHI"
pacman -S --noconfirm avahi >> /dev/zero
systemctl enable avahi-daemon >> /dev/zero

echo "Create user"
useradd -m homedudycz >> /dev/zero
printf "Apple1208\nApple1208\n" | passwd homedudycz >> /dev/zero

EOT
