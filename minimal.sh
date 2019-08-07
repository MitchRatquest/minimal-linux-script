#!/bin/sh
KERNEL_VERSION=5.0.2
BUSYBOX_VERSION=1.30.1
SYSLINUX_VERSION=6.03

function main() {
    topdir=$(pwd)
    install_fzy
    color_print green bold "Do you want a realtime linux kernel?"
    realtime=$(echo -ne "yes\nno" | ./fzzy)
    if [[ "$realtime" == "yes" ]]; then
        choose_kernel_rt_patch
    else
        choose_kernel_version
    fi
    choose_busybox_version
    choose_syslinux_version
    make_overlay
    make_busybox
    make_kernel
    apply_overlay
    compress_initrd
    make_iso
}

function install_fzy() {
    if [ ! -d fzy ]; then
        git clone https://github.com/jhawthorn/fzy.git
        cd fzy
        make
        cp fzy ../fzzy
        cd ../
    fi
}

function choose_kernel_version() {
    KERNEL_BASE_URL=https://mirrors.edge.kernel.org/pub/linux/kernel/
    major=$(echo -ne "2.6\n3.x\n4.x\n5.x\n" | ./fzzy)
    your_version=$(curl "$KERNEL_BASE_URL"v"$major/" | grep -Eo 'linux\-[0-9]\.[0-9]+\.[0-9]+' | uniq | ./fzzy)
    wget "$KERNEL_BASE_URL"v"$major/""$your_version".tar.gz
    tar xvf "$your_version".tar.gz
    color_print green bold "Kernel downloaded and extracted"
}

function choose_kernel_rt_patch() {
    PATCH_BASE_URL=https://mirrors.edge.kernel.org/pub/linux/kernel/projects/rt/
    major=$(curl "$PATCH_BASE_URL" | grep -Eo '>[0-9]\.[0-9]{1,2}(\.[0-9]+)?\/' | sed 's|>||g' | sed 's|/||g' | ./fzzy)
    your_version=$(curl "$PATCH_BASE_URL$major"/ | grep -Eo '>patch\-.*patch.gz' | sed 's|>||g' | sed 's|.patch.gz||g'| ./fzzy)
    wget  "$PATCH_BASE_URL$major"/"$your_version".patch.gz
    #get matching kernel version for your rt version
    KERNEL_BASE_URL=https://mirrors.edge.kernel.org/pub/linux/kernel/
    kernel_major="${major:0:1}.x"
    kernel_version=$(echo "$your_version" | sed 's|patch|linux|g' | sed 's|-rt.*||g').tar.gz
    wget "$KERNEL_BASE_URL"v"$kernel_major/""$kernel_version"
    tar xvf "$kernel_version"
    gunzip "$your_version".patch.gz
    cd "$topdir"/$(echo "$kernel_version" | sed 's|.tar.gz||g')
    patch -p1 < ../"$your_version".patch
    cd "$topdir"
    color_print green bold "Kernel downloaded, extracted, and patched"
}

function choose_busybox_version() {
    BUSYBOX_BASE_URL=https://busybox.net/downloads/
    busybox_version=$(curl "$BUSYBOX_BASE_URL" | grep -Eo "busybox-[0-9]\.[0-9]+(\.[0-9])?.tar.bz2" | sed 's|.tar.bz2||g' | uniq |  ./fzzy)
    wget "$BUSYBOX_BASE_URL""$busybox_version".tar.bz2
    tar xvf "$busybox_version".tar.bz2
    color_print green bold "Busybox downloaded"
}

function choose_syslinux_version() {
    SYSLINUX_BASE_URL=https://mirrors.edge.kernel.org/pub/linux/utils/boot/syslinux/
    SYSLINUX_VERSION=$(curl "$SYSLINUX_BASE_URL" | grep -Eo 'syslinux\-[0-9]\.[0-9]{2}\.tar\.gz' | uniq | ./fzzy)
    wget "$SYSLINUX_BASE_URL""$SYSLINUX_VERSION"
    tar xvf "$SYSLINUX_VERSION"
    color_print green bold "Syslinux downloaded"
}

function make_overlay() {
    cd "$topdir"
    mkdir -p isoimage
    mkdir -p overlay
    overlay="$topdir"/overlay
}

function make_busybox() {
    cd "$topdir"/"${busybox_version}"
    make distclean defconfig 
    sed -i "s|.*CONFIG_STATIC.*|CONFIG_STATIC=y|" .config
    make busybox install -j$(nproc)
    cd _install
    rm -f linuxrc
    mkdir dev proc sys
    echo '#!/bin/sh' > init
    echo 'dmesg -n 1' >> init
    echo 'mount -t devtmpfs none /dev' >> init
    echo 'mount -t proc none /proc' >> init
    echo 'mount -t sysfs none /sys' >> init
    echo 'setsid cttyhack /bin/sh' >> init
    chmod +x init
}

function make_kernel() {
    color_print green bold "Starting kernel configuration"
    cd "$topdir"/$(echo "$kernel_version" | sed 's|.tar.gz||g')
    bad_modules=$(make localmodconfig 2>&1 | awk '/\!/ {print $1}')
    lsmod | grep -v "${bad_modules[@]}" > mylsmod
    make clean
    color_print green bold "Starting kernel compilation"
    yes '' | make LSMOD=$(pwd)/mylsmod localmodconfig  #bzImage -j$(nproc)
    #yes '' | make LSMOD=$(pwd)/mylsmod mrproper localmodconfig 
    #make mrproper bzImage -j$(nproc)
    make -j$(nproc) bzImage
    cp arch/x86/boot/bzImage "$topdir"/isoimage/kernel.gz
    cd "$topdir"/isoimage
    cp "$topdir"/$(echo "${SYSLINUX_VERSION}" | sed 's|.tar.gz||g')/bios/core/isolinux.bin .
    cp "$topdir"/$(echo "${SYSLINUX_VERSION}" | sed 's|.tar.gz||g')/bios/com32/elflink/ldlinux/ldlinux.c32 .
    echo 'default kernel.gz initrd=rootfs.gz' > ./isolinux.cfg
}

function apply_overlay() {
    cp -a "$overlay/*" "$topdir"/"${busybox_version}"/_install
}

function compress_initrd() {
    cd "$topdir"/"${busybox_version}"/_install && find . | cpio -R root:root -H newc -o | gzip > "$topdir"/isoimage/rootfs.gz
    cd -
}

function make_iso() {
    cd "$topdir"/isoimage
    xorriso \
        -as mkisofs \
        -o "$topdir"/minimal_linux_live.iso \
        -b isolinux.bin \
        -c boot.cat \
        -no-emul-boot \
        -boot-load-size 4 \
        -boot-info-table \
    ./
    cd "$topdir"
}

function color_print() {
    case "$1" in
        red*)       color='\033[0;31m'  ;;
        orange*)    color='\033[0;33m'  ;;
        green*)     color='\033[0;32m'  ;;
        cyan*)      color='\e[96m'      ;;
        *)          color='\033[0m\e[0m';;
    esac
    nocolor='\033[0m\e[0m\e[0m'
    shift
    case "$1" in
        ul*)    modifier='\e[4m'    ;;
        inv*)   modifier='\e[7m'    ;;
        bold*)  modifier='\e[1m'    ;;
        *)      modifier='\e[0m'    ;;
    esac
    shift
    printf "${color}${modifier}$@${nocolor}\n"
}

