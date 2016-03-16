#!/bin/bash

touch /root/.bashrc >/dev/null 2>&1 || { echo "must be root"; exit 255; }

modprobe -r nbd
modprobe nbd max_part=5

lsmod | grep nbd >/dev/null 2>&1 || { echo "nbd not loaded"; exit 255; }
for app in qemu-img qemu-nbd fuser git virsh dirname basename wget; do {
    which $app >/dev/null 2>&1 || { echo "$app not found"; exit 255; }
} done

for config in configs/*xml; do {
    img=`awk -F \' '/file.*qcow2/ {print $2}' $config`
    name=`sed -n '/name/ {s/[^>]*>//;s/<.*//p;q}' $config`
    [ -e "$img" ] || {
        # image doesn't exist, download it?
        url=`awk "/^$name/ {print \\$2}" urls`
        pushd `dirname $img` >/dev/null
            wget $url || exit 255
        popd >/dev/null
    }
    echo "`date +%H:%M:%S` Job $name started"
    # inject the code
    echo -n "`date +%H:%M:%S` Inject the code ... "
    qemu-img snapshot -a init $img
    qemu-nbd -c /dev/nbd0 $img
    mount /dev/nbd0p1 mnt
    pushd mnt/opt >/dev/null
        sudo git clone ../../../../ pyroute2 >/dev/null 2>&1
    popd >/dev/null
    cp rc.local mnt/etc/rc.d/rc.local
    echo "done"
    echo -n "`date +%H:%M:%S` Sync disc ... "
    sync
    fuser -mk mnt
    umount mnt
    qemu-nbd -d /dev/nbd0 >/dev/null
    # start and monitor VM until stopped
    echo "done"
    echo -n "`date +%H:%M:%S` Start VM ... "
    virsh create $config >/dev/null
    echo "done"
    echo -n "`date +%H:%M:%S` Wait for shutdown ... "
    while :; do {
        virsh list | grep $name >/dev/null 2>&1 || break
        sleep 2
    } done
    echo "done"
    # fetch results
    echo -n "`date +%H:%M:%S` Save results ... "
    mkdir -p results/$name
    qemu-nbd -c /dev/nbd0 $img
    mount /dev/nbd0p1 mnt
    cp mnt/opt/pyroute2/*log results/$name
    sync
    fuser -mk mnt
    umount mnt
    qemu-nbd -d /dev/nbd0 >/dev/null
    echo "done"
    echo "`date +%H:%M:%S` Job $name finished"
} done
