# Prepare Hard drive
#wipefs -a /dev/sda
dd if=/dev/zero of=/dev/sda status=progress
printf "g\nn\n1\n\n+1M\nn\n2\n\n\nt\n1\n4\nw\n" | fdisk /dev/sda
mkfs.ext4 /dev/sda2

# Mount disk
mount /dev/sda2 /mnt

# Install base components
pacstrap -K /mnt base linux

# Setup fstab
genfstab -U /mnt >> /mnt/etc/fstab

# Setup hostname
echo "homeserver" >> /mnt/etc/hostname

# Setup locale
sed -i '/en_US.UTF-8/s/^#//g' /mnt/etc/locale.gen
echo "LANG=en_US.UTF-8" >> /mnt/etc/locale.conf

# CHROOT and setup
arch-chroot /mnt /bin/bash <<"EOT"

ln -sf /usr/share/zoneinfo/Europe/Warsaw /etc/localtime
locale-gen

pacman -S --noconfirm grub
grub-install /dev/sda
grub-mkconfig -o /boot/grub/grub.cfg

pacman -S --noconfirm dhcpcd
systemctl enable dhcpcd

pacman -S --noconfirm avahi
systemctl enable avahi-daemon

useradd -m homedudycz
printf "Apple1208\nApple1208\n" | passwd homedudycz

EOT

