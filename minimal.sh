#!/bin/bash
set -e
KERNEL_VERSION=5.0.2
BUSYBOX_VERSION=1.30.1
SYSLINUX_VERSION=6.03

function main() {
    topdir=$(pwd)
    install_fzf
    color_print green bold "Do you want a realtime linux kernel?"
    realtime=$(echo -ne "no\nyes" | fzf)
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

    dvorak_setting
    apply_overlay
    compress_initrd

    make_iso
}

function install_fzf() {
   if doesnt_exist fzf; then
       machine=$(uname -m)
       case $machine in
           x86_64*) target=amd64 ;;
           i686*)   target=386   ;;
           armv7*)  target=arm7  ;;
           386*)    target=386   ;;
           amd64*)  target=amd64 ;;
       esac
       wget -q "https://github.com/junegunn/fzf-bin/releases/download/0.18.0/fzf-0.18.0-linux_${target}.tgz" -O fzf.tgz
       tar xvf fzf.tgz
       rm fzf.tgz
   fi
}

function fzf() {
     ./fzf --height 40% --layout=reverse
}

function choose_kernel_version() {
    KERNEL_BASE_URL=https://mirrors.edge.kernel.org/pub/linux/kernel/
    color_print green bold "Please select the major version: "
    major=$(echo -ne "2.6\n3.x\n4.x\n5.x\n" | tac |  fzf)
    color_print green bold "Please select your exact version: "
    your_version=$(curl -s "$KERNEL_BASE_URL"v"$major/" | grep -Eo 'linux\-[0-9]\.[0-9]+\.[0-9]+' | uniq | tac  | fzf)
    wget "$KERNEL_BASE_URL"v"$major/""$your_version".tar.gz
    tar xvf "$your_version".tar.gz
    kernel_version=$your_version
    color_print green bold "Kernel downloaded and extracted"
}

function choose_kernel_rt_patch() {
    PATCH_BASE_URL=https://mirrors.edge.kernel.org/pub/linux/kernel/projects/rt/
    color_print green bold "Please select the major version: "
    major=$(curl -s "$PATCH_BASE_URL" | grep -Eo '>[0-9]\.[0-9]{1,2}(\.[0-9]+)?\/' | sed 's|>||g' | sed 's|/||g' | tac | fzf)
    color_print green bold "Please select your exact version: "
    your_version=$(curl -s "$PATCH_BASE_URL$major"/ | grep -Eo '>patch\-.*patch.gz' | sed 's|>||g' | sed 's|.patch.gz||g'| tac | fzf)
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
    color_print green bold "Please pick a busybox version:"
    BUSYBOX_BASE_URL=https://busybox.net/downloads/
    busybox_version=$(curl -s "$BUSYBOX_BASE_URL" | grep -Eo "busybox-[0-9]\.[0-9]+(\.[0-9])?.tar.bz2" | sed 's|.tar.bz2||g' | uniq | tac | fzf)
    wget "$BUSYBOX_BASE_URL""$busybox_version".tar.bz2
    color_print green bold "Busybox downloaded"
    tar xf "$busybox_version".tar.bz2
    color_print green bold "Busybox extracted"
}

function choose_syslinux_version() {
    if [ -z $SYSLINUX_VERSION ]; then
        SYSLINUX_BASE_URL=https://mirrors.edge.kernel.org/pub/linux/utils/boot/syslinux/
        SYSLINUX_VERSION=$(curl -s "$SYSLINUX_BASE_URL" | grep -Eo 'syslinux\-[0-9]\.[0-9]{2}\.tar\.gz' | uniq | tac | fzf)
        wget "$SYSLINUX_BASE_URL""$SYSLINUX_VERSION"
        tar xf "$SYSLINUX_VERSION"
        color_print green bold "Syslinux downloaded"
    else
        wget https://mirrors.edge.kernel.org/pub/linux/utils/boot/syslinux/syslinux-"${SYSLINUX_VERSION}".tar.gz
        tar xvf syslinux-"${SYSLINUX_VERSION}".tar.gz
    fi
}

function exists() { [ -e "$1" ]; }
function doesnt_exist() { [ ! -e "$1" ]; }

function make_overlay() {
    cd "$topdir"
    mkdir -p isoimage
    mkdir -p overlay
    overlay="$topdir"/overlay
}

function make_busybox() {
    cd "$topdir"/"${busybox_version}"
    if exists _install; then
        rm -rf _install
    fi
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
    color_print green bold "Starting kernel compilation"
    yes '' | make localyesconfig bzImage -j$(nproc)
    make -j$(nproc) bzImage
    cp arch/x86/boot/bzImage "$topdir"/isoimage/kernel.gz
    cd "$topdir"/isoimage
    cp "$topdir"/$(echo syslinux-"${SYSLINUX_VERSION}" | sed 's|.tar.gz||g')/bios/core/isolinux.bin .
    cp "$topdir"/$(echo syslinux-"${SYSLINUX_VERSION}" | sed 's|.tar.gz||g')/bios/com32/elflink/ldlinux/ldlinux.c32 .
    echo 'default kernel.gz initrd=rootfs.gz' > isolinux.cfg
}

function dvorak_setting() {
    mkdir -p "$topdir"/overlay/usr/share/kmaps
    cp "$topdir"/dvorak.kmap "$topdir"/overlay/usr/share/kmaps
    sed -i 's|setsid cttyhack /bin/sh|loadkmap < /usr/share/kmaps/dvorak.kmap\nsetsid cttyhack /bin/sh|g' "$topdir"/"$busybox_version"/_install/init
}

function apply_overlay() {
    cp -a "$overlay/"* "$topdir"/"${busybox_version}"/_install
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

function fancyf() {
    fzf --prompt="Please select any of the below: " --height 40% --layout=reverse \
    --preview '[[ $(file {} | grep -ic text ) == 0 ]] && echo {} is not a text file || ([[ $(stat --format %F {}) == "directory" ]] && ls {} || cat {}) 2> /dev/null | head -n 100' \
    --preview-window=right:60%
}

export FZF_DEFAULT_OPTS='--height 40% --layout=reverse'
export FZF_DEFAULT_COMMAND='ls'

main "$@"
