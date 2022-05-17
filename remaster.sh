#!/bin/bash
set -ex
. /etc/remaster.conf
if [[ "${integrate_installer}" == "true" ]] ; then
    grep "boot=live" /proc/cmdline && /installer
fi
#install dependencies
apt install grub-pc-bin grub-efi squashfs-tools xorriso mtools curl -y

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
echo "nameserver 1.1.1.1" > $rootfs/etc/resolv.conf

#live-boot install
chroot $rootfs apt install live-config live-boot --no-install-recommends -y
chroot $rootfs apt autoremove -y
echo -e "live\nlive\n" | chroot $rootfs passwd

#mount empty file and directories
for i in dev sys proc run tmp root media mnt; do
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
chroot $rootfs apt clean -y

install /etc/remaster.conf $rootfs/etc/remaster.conf

#create squashfs
if [[ ! -f iso/live/filesystem.squashfs ]] ; then
    mksquashfs $rootfs iso/live/filesystem.squashfs -comp gzip -wildcards
fi

#write grub file
grub=iso/boot/grub/grub.cfg
echo "insmod all_video" > $grub
echo "set timeout=3" >> $grub
echo "set timeout_style=menu" >> $grub
dist=$(cat /etc/os-release | grep ^PRETTY_NAME | cut -f 2 -d '=' | head -n 1 | sed 's/\"//g')
for k in $(ls /boot/vmlinuz-*) ; do
    ver=$(echo $k | sed "s/.*vmlinuz-//g")
    if [[ -f /boot/initrd.img-$ver ]] ; then
        cp -f $rootfs/boot/vmlinuz-$ver iso/boot
        cp -f $rootfs/boot/initrd.img-$ver iso/boot
        if [[ -f $rootfs/install && "${integrate_installer}" == "true" ]] ; then
            echo "menuentry \"Install $dist ($ver)\" {" >> $grub
            echo "    linux /boot/vmlinuz-$ver boot=live init=/install" >> $grub
            echo "    initrd /boot/initrd.img-$ver" >> $grub
            echo "}" >> $grub
        fi
        if [[ "${live_boot}" == "true" ]] ; then
            echo "menuentry \"$dist ($ver)\" {" >> $grub
            echo "    linux /boot/vmlinuz-$ver boot=live live-config quiet splash" >> $grub
            echo "    initrd /boot/initrd.img-$ver" >> $grub
            echo "}" >> $grub
        fi
    fi
done

#umount all
umount -v -lf -R /tmp/work/* || true

# create iso
grub-mkrescue iso/ -o live-image-$(date +%s).iso



