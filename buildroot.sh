#!/bin/bash
#space separated package names will be installed via static-get
#for example: EXTRA_PACKAGES=(gcc bash gawk)
EXTRA_PACKAGES=()
DVORAK_KEYBOARD=no
#no extra packages, no dvorak:
#br-rootfs.iso:    16 MB
#actual space used on rootfs: 9.1 MB

function main() {
    get_buildroot
    set_configurations
    create_overlay
    populate_overlay
    install_extras
    cd "$TOPDIR" && make -j$(nproc)
    display_message
    boot_image
}

function get_buildroot() {
    cd "$TOPDIR"
    if [ ! -d buildroot ]; then
        commit=9b9abb0dd03114347d10d09131ad4e96f5583514
        git clone https://github.com/buildroot/buildroot.git
        cd buildroot
        git checkout "$commit"
    fi
    cd "$TOPDIR"
}

function set_configurations() {
    cd "$TOPDIR"
    if [ ! -f .initial_br ]; then
        make O=$(pwd) -C buildroot/ defconfig BR2_DEFCONFIG=../br_defconfig
        touch .initial_br
    fi
}

function create_overlay() {
    cd "$TOPDIR"
    mkdir -p overlay
}

function populate_overlay() {
    create_sysvinit 'S98-networkup' '#!/bin/sh
ip link set up eth0
udhcpc eth0
exit 0'
    install_dvorak_kmap
}


function install_dvorak_kmap() {
    if [ "$DVORAK_KEYBOARD" == 'yes' ]; then
        install_a_file usr/share/kmaps dvorak.kmap
        create_sysvinit 'S99-dvorak' '#!/bin/sh
loadkmap < /usr/share/kmaps/dvorak.kmap
exit 0'
    fi
}

function install_a_file() {
    cd "$TOPDIR"
    location="$1"
    file="$2"
    mkdir -p overlay/"$location"
    cp "$1" overlay/"$location"/"$1"
}

function create_sysvinit() {
    cd "$TOPDIR"
    overlay_dir=overlay/etc/init.d
    mkdir -p "$overlay_dir"
    name="$1"
    shift
    contents="$@"
    echo -ne > "$overlay_dir"/"$name"
    echo "$contents" >> "$overlay_dir"/"$name"
    chmod 777 "$overlay_dir"/"$name"
}

function install_extras() {
    cd "$TOPDIR"
    if [ ! -z "$EXTRA_PACKAGES" ]; then
        if [ ! -f static-get ]; then
            wget https://raw.githubusercontent.com/minos-org/minos-static/master/static-get
            chmod 777 static-get
        fi
        cd overlay
        for package in "${EXTRA_PACKAGES[@]}"; do
            ../static-get -o "$package" "$package"
            tar xvf "$package"
        done
    fi
}

function display_message() {
    color_print green bold 'Thanks for trying this out!
By default, this has made a very minimal image using buildroot
'

    color_print green bold 'If you want to change any settings in buildroot
such as packages, build systems, filesystem types, etc, type'; color_print normal inv 'make menuconfig'
    color_print green bold 'If you want to change kernel settings, type'; color_print normal inv 'make linux-menuconfig'
    color_print green bold 'To change the busybox config, type'; color_print normal inv  'make busybox-menuconfig'
    color_print green bold 'If you use uboot, type'; color_print normal inv 'make uboot-menuconfig'
    color_print green bold 'Ff you use uClibc, type'; color_print normal inv 'make uclibc-menuconfig'
    echo -ne '\n\n\n'
    color_print green bold 'I wish someone had told these things when starting linux devops:
/ in menuconfig enables a search function
and that you can jump to any options by 1-9, with the top search return being 1

pressing space on an option enables/disables it
* means its built in
m means it will be built as a module
h will show some helpful information

the highlighted letter at in each option is a hotkey to jump to it
by pressing that letter
for example (each new line means "press enter"):
make linux-menuconfig
d
sssssss

will get you into the sound card support device drivers menu

you could also type (each new line means "press enter"):
/
sound
1
to get there too!'
}

function boot_image() {
    cd "$TOPDIR"
    cp images/rootfs.iso9660 br-rootfs.iso
    qemu-system-x86_64 -m 512M -cdrom br-rootfs.iso -boot d -vga std -smp 4 -device e1000
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

TOPDIR=$(pwd)
main "$@"