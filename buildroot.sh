#!/bin/bash
EXTRA_PACKAGES=(gcc bash)


function main() {
    get_buildroot
    set_configurations
    create_overlay
    populate_overlay
    install_extras
    make -j$(nproc)
    boot_image
}

function get_buildroot() {
    if [ ! -d buildroot ]; then
        commit=9b9abb0dd03114347d10d09131ad4e96f5583514
        git clone https://github.com/buildroot/buildroot.git
        cd buildroot
        git checkout "$commit"
        cd ..
    fi
}

function set_configurations() {
    if [ ! -f .initial_br ]; then
        make O=$PWD -C buildroot/ defconfig BR2_DEFCONFIG=../br_defconfig
        touch .initial_br
    fi
}

function create_overlay() {
    mkdir -p overlay
}

function populate_overlay() {
    mkdir -p overlay/usr/share/kmaps
    cp dvorak.kmap overlay/usr/share/kmaps/dvorak.kmap
    create_sysvinit 'S99-dvorak' '#!/bin/sh
loadkmap < /usr/share/kmaps/dvorak.kmap
exit 0'
    create_sysvinit 'S98networkup' '#!/bin/sh
ip link set up eth0
udhcpc eth0
exit 0'
}

function create_sysvinit() {
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
    if [ ! -z "$EXTRA_PACKAGES" ]; then
        if [ ! -f static-get ]; then
            wget https://raw.githubusercontent.com/minos-org/minos-static/master/static-get
            chmod 777 static-get
        fi
        cd overlay
        for package in "${EXTRA_PACKAGES[@]}"; do
            ../static-get -x "$package"
        done
    fi
}


function boot_image() {
    qemu-system-x86_64 -m 512M -cdrom images/rootfs.iso9660 -boot d -vga std -smp 4 -device e1000
}

main "$@"