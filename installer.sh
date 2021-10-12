#!/bin/bash
export PATH=/usr/bin:/usr/sbin:/bin:/sbin
modprobe efivars || true
# installation tool for remaster images
msg(){
    echo -e "\033[32;1m$1\033[;0m"
}
echo "If you press any key in 3 seconds, create debug shell"
echo "Waiting 3 seconds..."
if read -n 1 -t 3 -s ; then
    PS1="\[\033[32;1m\]>>>\[\033[;0m\] " /bin/bash --norc --noprofile
fi
source /etc/remaster.conf
if [[ $$ -eq 0 ]] ; then
    mount -t devtmpfs devtmpfs /dev || true
    mount -t proc proc /proc || true
    mount -t sysfs sysfs /sys || true
    mount -t efivarfs efivarfs /sys/firmware/efi/efivars || true
fi
mkdir /source /target || true
mount /dev/loop0 /source || true
fallback(){
        echo -e "\033[31;1mInstallation failed.\033[;0m"
        echo -e "Creating a shell for debuging. Good luck :D"
        PS1="\[\033[32;1m\]>>>\[\033[;0m\] " /bin/bash --norc --noprofile
        if [[ $$ -eq 0 ]] ; then
            echo o > /proc/sysrq-trigger
        else
            exit 1
        fi
}

if [[ "$debug" != "false" ]] ; then
    PS1="\[\033[32;1m\]>>>\[\033[;0m\]" /bin/bash --norc --noprofile
fi

if [[ "$partitioning" == "true" ]] ; then
    dd if=/dev/zero of=/dev/${DISK} bs=512 count=1
    sync && sleep 1
    if [[ -d /sys/firmware/efi ]] ; then
        yes | parted /dev/${DISK} mktable gpt || fallback
        yes | parted /dev/${DISK} mkpart primary fat32 1 "100MB" || fallback
        yes | parted /dev/${DISK} mkpart primary fat32 100MB "100%" || fallback
        sync && sleep 1
        yes | mkfs.vfat /dev/${DISK}1 || fallback
        sync && sleep 1
        yes | mkfs.ext4  /dev/${DISK}2 || fallback
        yes | parted /dev/${DISK} set 1 esp on || fallback
        sync && sleep 1
        mount /dev/${DISK}2  /target || fallback
        mkdir -p /target/boot/efi || true
        mount /dev/${DISK}1 /target/boot/efi  || fallback
    else
        yes | parted /dev/${DISK} mktable msdos || fallback
        yes | parted /dev/${DISK} mkpart primary fat32 1 "100%" || fallback
        sync && sleep 1
        yes | mkfs.ext4 /dev/${DISK}1  || fallback
        yes | parted /dev/${DISK} set 1 boot on || fallback
        sync && sleep 1
        mount /dev/${DISK}1 /target  || fallback
    fi
else
    echo "Please input rootfs part (example sda2)"
    read rootfs
    echo "Please input mbr (example sda)"
    read DISK
    mount /dev/$rootfs /target
    if [[ -d /sys/firmware/efi ]] ; then
        echo "Please input efi part (example sda1)"
        read efifs
        mkdir -p /target/boot/efi
        mount /dev/$efifs /target/boot/efi
    fi
fi
#rsync -avhHAX /source/ /target
ls /source/ | xargs -n1 -P$(nproc) -I% rsync -avhHAX /source/% /target/  || fallback

if [[ "$partitioning" == "true" ]] ; then
    if [[ -d /sys/firmware/efi ]] ; then
        echo "/dev/${DISK}2 /               ext4    errors=remount-ro        0       1" > /target/etc/fstab  || fallback
        echo "/dev/${DISK}1 /boot/efi       vfat    umask=0077               0       0" >> /target/etc/fstab  || fallback
    else
        echo "/dev/${DISK}1 /               ext4    errors=remount-ro        0       1" > /target/etc/fstab  || fallback
    fi
else
    echo "Please write fstab file. Press any key to open editor."
    read -n 1 -s
    nano /target/etc/fstab
fi

for i in dev sys proc run 
do
    mkdir -p /target/$i || true 
    mount --bind /$i /target/$i  || fallback
done
if [[ -d /sys/firmware/efi ]] ; then
    mount --bind /sys/firmware/efi/efivars /target/sys/firmware/efi/efivars || fallback
fi
chroot /target apt-get purge live-boot* live-config* live-tools --yes || true
chroot /target apt-get autoremove --yes || true
chroot /target update-initramfs -u -k all  || fallback
if [[ "${remove_user}" == "true" ]] ; then
    chroot /target useradd -m -s /bin/bash $username || fallback
    mkdir /target/home/$username || true
    chroot /target chown $username /home/$username
    echo -e "$password\n$password\n" | chroot /target passwd $username
    #echo -e "$password\n$password\n" | chroot /target passwd root
    for grp in cdrom floppy sudo audio dip video plugdev netdev bluetooth lpadmin scanner ; do
        chroot /target usermod -aG $grp $username || true
    done
fi
if [[ -d /sys/firmware/efi ]] ; then
    chroot /target mount -t efivarfs efivarfs /sys/firmware/efi/efivars || true
    chroot /target grub-install /dev/${DISK} --target=x86_64-efi || fallback
else
    chroot /target grub-install /dev/${DISK} --target=i386-pc || fallback
fi
echo "GRUB_DISABLE_OS_PROBER=true" >> /target/etc/default/grub
chroot /target update-grub  || fallback
[[ -f /target/install ]] && rm -f /target/install || true
umount -f -R /target/* || true
sync  || fallback

if [[ "$debug" != "false" ]] ; then
    PS1="\[\033[32;1m\]>>>\[\033[;0m\] " /bin/bash --norc --noprofile
else
    echo "Installation done. System restarting in 10 seconds. Press any key to restart immediately."
    read -t 10 -n 1 -s
fi
if [[ $$ -eq 1 ]] ; then
    echo b > /proc/sysrq-trigger
else
    exit 0
fi
