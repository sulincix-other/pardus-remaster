#!/bin/bash
set -ex
rm -rf /var/remaster || true
mkdir -p /var/remaster
cd /var/remaster
source /etc/remaster.conf
if [[ "${integrate_installer}" == "true" ]] ; then
    grep "boot=live" /proc/cmdline && /installer
fi
#install dependencies
apt install grub-pc-bin grub-efi squashfs-tools xorriso mtools curl qemu-utils -y

#overlayfs mount
mount -t tmpfs tmpfs /tmp || true
mkdir -p /tmp/work/source /tmp/work/a /tmp/work/b /tmp/work/target /tmp/work/empty \
         iso/live/ iso/boot/grub/|| true
touch /tmp/work/empty-file
umount -v -lf -R /tmp/work/* || true
mount --bind / /tmp/work/source
mount -t overlay -o lowerdir=/tmp/work/source,upperdir=/tmp/work/a,workdir=/tmp/work/b overlay /tmp/work/target

#resolv.conf fix
export rootfs=/tmp/work/target
rm -f $rootfs/etc/resolv.conf || true
cat /etc/resolv.conf > $rootfs/etc/resolv.conf

#live-boot install
chroot $rootfs apt install live-config live-boot --no-install-recommends -y
chroot $rootfs apt autoremove -y
echo -e "live\nlive\n" | chroot $rootfs passwd
rm -f $rootfs/etc/initramfs-tools/conf.d/resume || true

#mount empty file and directories
for i in dev sys proc run tmp root media mnt var/remaster; do
    mount -v --bind /tmp/work/empty $rootfs/$i
done

mount --bind /tmp/work/empty-file $rootfs/etc/fstab

if [[ "${integrate_installer}" == "true" ]] ; then
    #integrate installer (automated installer / optional)
    install /usr/lib/pardus/remaster/install $rootfs/install
    [[ -f $rootfs/install ]] && chmod +x $rootfs/install
fi

#install packages
chroot $rootfs apt install curl nano rsync parted grub-pc-bin grub-efi dosfstools -y

#clear rootfs
find $rootfs/var/log -type f | xargs rm -f
find $rootfs/var/lib/apt/lists -type f | xargs rm -f
rm -rf $rootfs/home/*/.cache
chroot $rootfs apt clean -y

install /etc/remaster.conf $rootfs/etc/remaster.conf

#create squashfs
if [[ ! -f iso/live/filesystem.squashfs ]] ; then
    mksquashfs $rootfs iso/live/filesystem.squashfs -comp xz -wildcards
fi

#write grub file
grub=iso/boot/grub/grub.cfg
echo "insmod all_video" > $grub
echo "set timeout=3" >> $grub
echo "set timeout_style=menu" >> $grub
dist=$(cat /etc/os-release | grep ^PRETTY_NAME | cut -f 2 -d '=' | head -n 1 | sed 's/\"//g')
ver=$(uname -r)
if [[ -f /boot/vmlinuz-$ver ]] ; then
    cp -f $rootfs/boot/vmlinuz-$ver iso/boot
    chroot $rootfs update-initramfs -u -k $ver
    cp -f $rootfs/boot/initrd.img-$ver iso/boot
    if [[ -f $rootfs/install && "${integrate_installer}" == "true" ]] ; then
        echo "menuentry \"Install $dist\" {" >> $grub
        echo "    linux /boot/vmlinuz-$ver boot=live init=/install quiet" >> $grub
        echo "    initrd /boot/initrd.img-$ver" >> $grub
        echo "}" >> $grub
    fi
    if [[ "${live_boot}" == "true" ]] ; then
        echo "menuentry \"$dist ($ver)\" {" >> $grub
        echo "    linux /boot/vmlinuz-$ver boot=live live-config quiet components timezone=Europe/Istanbul locales=tr_TR.UTF-8,en_US.UTF-8 keyboard-layouts=tr username=pardus hostname=pardus user-fullname=Pardus vga=791 noswap " >> $grub
        echo "    initrd /boot/initrd.img-$ver" >> $grub
        echo "}" >> $grub
    fi
fi

#umount all
umount -v -lf -R /tmp/work/* || true

# create img
size=$(du -s iso | cut -f 1)
qemu-img create "rootfs.img" $(($size*1080+(300*1024*1024)))
parted "rootfs.img" mklabel msdos
echo Ignore | parted "rootfs.img" mkpart primary fat32 2048s 100M
echo Ignore | parted "rootfs.img" mkpart primary ext2 101M 100%
losetup -d /dev/loop0 || true
loop=$(losetup --partscan --find --show "rootfs.img" | grep "/dev/loop")
mkfs.vfat ${loop}p1
yes | mkfs.ext4 ${loop}p2
mount ${loop}p2 /mnt
mkdir -p /mnt/boot/efi
mount ${loop}p1 /mnt/boot/efi
cp -prfv iso/* /mnt
sync
echo "(hd0)   ${loop}" > /mnt/boot/grub/device.map
grub-install --removable --grub-mkdevicemap=/mnt/boot/grub/device.map --target=i386-pc --root-directory=/mnt ${loop}
grub-install --removable --grub-mkdevicemap=/mnt/boot/grub/device.map --target=x86_64-efi --root-directory=/mnt --efi-directory /mnt/boot/efi ${loop}
sync
umount /mnt/boot/efi
umount /mnt
losetup -d ${loop}* || true
if [[ "$1" != "" ]] ; then
    mv rootfs.img "$1"
fi
