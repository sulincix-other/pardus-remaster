#!/bin/bash
set -e
if cat /proc/cmdline | grep "boot=live" &>/dev/null; then
    mkdir /source /target
    mount /dev/loop0 /source
    # TODO: Look here again :)
    if [ -d /sys/firmware/efi ] ; then
        echo -e "g\nn\n\n+100M\nn\n\n\nw\nt\n\n1\nw\n" | fdisk /dev/sda
        mkfs.vfat /dev/sda1
        mkfs.ext4 /dev/sda2
        mount /dev/sda2 /target
    else
        echo -e "o\nn\np\n\n\n\nw\n" | fdisk /dev/sda
        mkfs.ext4 /dev/sda1
        mount /dev/sda1 /target
    fi
    cp -prfv /source/* /target/
fi


#Define and create directories
workdir=/root/.workdir
mkdir -p $workdir
isowork=/root/.isowork
mkdir -p $isowork/live
mkdir -p $isowork/boot/grub/
touch /root/.dummy

#binding and symlink directories
for dir in bin lib32 boot lib64 libx32 opt sbin usr etc lib var home
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
apt-get install live-boot live-config mtools xorriso squashfs-tools dialog grub-pc-bin grub-efi --yes
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
# create iso image
grub-mkrescue $isowork -o ./live-image-amd64.iso
rm -rf $isowork $workdir /root/.dummy

