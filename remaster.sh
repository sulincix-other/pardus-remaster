#!/bin/bash
if [ $UID -ne 0 ] ; then
    echo "You must be root!"
    exit 1
fi
self="$(realpath $0)"
if ! [ "$self" == "/usr/bin/remaster" ] ; then
    install "$self" "/usr/bin/remaster"
    echo -e "\033[32;1mSelf script installation done.\n Now you should remove the script and run \"\033[31;1mremaster\033[32;1m\" command.\033[;0m"
    exit 0
fi
fallback(){
while true
do
    /bin/bash
done
}
set -e
if cat /proc/cmdline | grep "boot=live" &>/dev/null; then
    mkdir /source /target || true
    mount /dev/loop0 /source || true
    # TODO: Look here again :)
    if [ -d /sys/firmware/efi ] ; then
        echo -e "g\ny\nw\n" | fdisk /dev/sda
        echo -e "n\n\n\n+100M\ny\n\nw\n" | fdisk /dev/sda
        echo -e "n\n\n\n\ny\n\nw\n" | fdisk /dev/sda
        mkfs.vfat /dev/sda1
        mkfs.ext4 /dev/sda2
        mount /dev/sda2 /target
    else
        echo -e "o\nn\np\n\n\n\ny\nw\n" | fdisk /dev/sda
        mkfs.ext4 /dev/sda1
        mount /dev/sda1 /target
    fi
    #rsync -avhHAX /source/ /target
    ls /source/ | xargs -n1 -P$(nproc) -I% rsync -avhHAX /source/% /target/
    if [ -d /sys/firmware/efi ] ; then
        echo "/dev/sda2 /               ext4    errors=remount-ro        0       1" > /target/etc/fstab
        echo "/dev/sda1 /boot/efi       vfat    umask=0077               0       1" >> /target/etc/fstab
    else
        echo "/dev/sda1 /               ext4    errors=remount-ro        0       1" > /target/etc/fstab
    fi
    if [ -d /sys/firmware/efi ] ; then
        mkdir -p /target/boot/efi || true
        mount /dev/sda1 /target/boot/efi
    fi
    for i in dev sys proc run
    do
        mkdir -p /target/$i || true
        mount --bind /$i /target/$i
    done
    chroot /target grub-install /dev/sda
    chroot /target apt-get purge live-boot* live-config* --yes || true
    chroot /target apt-get autoremove --yes || true
    chroot /target update-initramfs -u -k all
    chroot /target update-grub
    umount -f -R /target/* || true
    sync
    echo b > /proc/sysrq-trigger
fi


#Define and create directories
workdir=/root/.workdir
mkdir -p $workdir
isowork=/root/.isowork
mkdir -p $isowork/live
mkdir -p $isowork/boot/grub/
touch /root/.dummy

#binding and symlink directories
for dir in bin lib32 boot lib64 libx32 opt sbin usr etc lib var home ortak-alan
do
    if [ "" == "$(readlink /$dir)" ]
    then
        mkdir -p $workdir/$dir
        umount -lf -R $workdir/$dir 2>/dev/null || true
        mount --bind /$dir $workdir/$dir
    else
        rm -f $workdir/$dir 2>/dev/null || true
        ln -s $(readlink /$dir) $workdir/$dir
    fi
done

#create excluded directories as empty
for dir in media mnt root dev sys proc run tmp home
do
    mkdir -p $workdir/$dir
done

#bind fstab as dummy
mount --bind /root/.dummy $workdir/etc/fstab

#prepare and take image then clean
apt-get install live-boot live-config mtools xorriso squashfs-tools dialog rsync grub-pc-bin grub-efi --yes
apt clean
[ -f $isowork/live/filesystem.squashfs ] || mksquashfs $workdir $isowork/live/filesystem.squashfs -comp gzip -wildcards
cp -pf "/boot/vmlinuz-$(uname -r)" $isowork/live/vmlinuz
cp -pf "/boot/initrd.img-$(uname -r)" $isowork/live/initrd.img
apt-get purge live-boot* live-config* --yes || true
apt-get autoremove --yes || true

#unbinding and clearing
umount -lf $workdir/etc/fstab || true
umount -lf -R $workdir/* 2>/dev/null || true
rm -f $workdir/* || true
rmdir $workdir/* || true
rmdir $workdir || true

#create boot config
echo "insmod all_video" > $isowork/boot/grub/grub.cfg
echo "menuentry $(cat /etc/os-release | grep ^NAME | sed s/.*=//) {" >> $isowork/boot/grub/grub.cfg
echo "    linux /live/vmlinuz boot=live components locales=tr_TR.UTF-8,en_US.UTF-8 keyboard-layouts=tr" >> $isowork/boot/grub/grub.cfg
echo "    initrd /live/initrd.img" >> $isowork/boot/grub/grub.cfg
echo "}" >> $isowork/boot/grub/grub.cfg
#create install config
echo "menuentry Install $(cat /etc/os-release | grep ^NAME | sed s/.*=//) {" >> $isowork/boot/grub/grub.cfg
echo "    linux /live/vmlinuz boot=live components init=/usr/bin/remaster" >> $isowork/boot/grub/grub.cfg
echo "    initrd /live/initrd.img" >> $isowork/boot/grub/grub.cfg
echo "}" >> $isowork/boot/grub/grub.cfg
# create iso image
grub-mkrescue $isowork -o ./live-image-amd64.iso
rm -rf $isowork $workdir /root/.dummy

