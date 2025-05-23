#!/bin/bash
set -e
KERNEL_VERSION=5.9.16
BUSYBOX_VERSION=1.33.0
SYSLINUX_VERSION=syslinux-6.03.tar.gz
FZF_VERSION=0.25.0
#defconfig modconfig builtin current
KERNEL_CONFIG=defconfig
#defconfig = linux kernel defconfig
#modconfig = current running kernel's config, only the modules currently loaded, aka output of lsmod
#builtin = modconfig, but built in instead of modules, no modules directory created
#current = current kernel's config, warning could result in huge module directory!
#iso sizes:
#defconfig: about 6MB
#builtin:   about 9MB
#current: about 1199MB    (debian 9/bunsenlabs helium)
DVORAK=no

function main() {
    topdir=$(pwd)
    install_fzf
    prompt "Do you want a realtime linux kernel?"
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
    #copy_firmware

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
       wget -q "https://github.com/junegunn/fzf/releases/download/${FZF_VERSION}/fzf-${FZF_VERSION}-linux_${target}.tar.gz" -O fzf.tgz
       tar xvf fzf.tgz
       rm fzf.tgz
   fi
}

function choose_kernel_version() {
    MAJOR_LINUX_VERSIONS=( 6.x 5.x 4.x 3.x 2.6 )
    message=$( for version in "${MAJOR_LINUX_VERSIONS[@]}"; do echo $version; done )
    prompt "Please select the major version: "
    major_linux_version=$(echo "$message"| fzf)
    response_prompt "$major_linux_version"
    prompt "Please select your exact version: "
    linux_version=$(curl -s "$KERNEL_BASE_URL"v"$major_linux_version/" | grep -Eo 'linux\-[0-9]\.[0-9]+(\.[0-9]+)?' | uniq | tac | fzf)
    response_prompt "$linux_version"
    if [ -f "$linux_version".tar.gz ]; then
        prompt "Kernel already downloaded"
    else
        prompt "Downloading kernel"
        wget "$KERNEL_BASE_URL"v"$major_linux_version"/"$linux_version".tar.gz
    fi
    if [ ! -d "${linux_version}" ]; then
        prompt "Extracting kernel"
        tar xf "$linux_version".tar.gz
    fi
    kernel_version=$linux_version
    prompt "Kernel downloaded and extracted"
}

function choose_kernel_rt_patch() {
    prompt "Please select the major version: "
    patch_major_version=$(curl -s "$PATCH_BASE_URL" | grep -Eo '>[0-9]\.[0-9]{1,2}(\.[0-9]+)?\/' | sed 's|>||g' | sed 's|/||g' | tac | fzf)
    response_prompt "$patch_major_version"
    prompt "Please select your exact version: "
    patch_version=$(curl -s "$PATCH_BASE_URL$patch_major_version"/ | grep -Eo '>patch\-.*patch.gz' | sed 's|>||g' | sed 's|.patch.gz||g'| tac | fzf)
    response_prompt "$patch_version"
    if [ ! -f "$patch_version".patch.gz ] || [ ! -f "$patch_version".patch ]; then
        prompt "Downloading patch"
        wget "$PATCH_BASE_URL$patch_major_version"/"$patch_version".patch.gz
    fi
    #get matching kernel version for your rt version
    major_linux_version="${patch_major_version:0:1}.x"
    linux_version=$(echo "$patch_version" | sed 's|patch|linux|g' | sed 's|-rt.*||g')
    if [ -f "$linux_version".tar.gz ]; then
        prompt "Kernel already downloaded"
    else
        prompt "Downloading kernel"
        wget "$KERNEL_BASE_URL"v"$major_linux_version"/"$linux_version".tar.gz
    fi
    prompt "Extracting kernel"
    tar xf "$linux_version".tar.gz
    gunzip -f "$patch_version".patch.gz
    cd "$topdir"/$(echo "$linux_version" | sed 's|.tar.gz||g')
    if [ ! -f .kernel_patched ]; then
        prompt "Applying realtime patch"
        patch -p1 < ../"$patch_version".patch
        touch .kernel_patched
    else
        prompt "Kernel already patched"
    fi
    cd "$topdir"
    prompt "Kernel downloaded, extracted, and patched"
}

function choose_busybox_version() {
    prompt "Please pick a busybox version:"
    busybox_version=$(curl -s "$BUSYBOX_BASE_URL" | grep -Eo "busybox-[0-9]\.[0-9]+(\.[0-9])?.tar.bz2" | sed 's|.tar.bz2||g' | uniq | tac | fzf)
    response_prompt "$busybox_version"
    if [ ! -f "$busybox_version".tar.bz2 ]; then
        prompt "Downloading busybox"
        wget "$BUSYBOX_BASE_URL""$busybox_version".tar.bz2
        prompt "Busybox downloaded"
        prompt "Extracting busybox"
        tar xf "$busybox_version".tar.bz2
        prompt "Busybox extracted"
    elif [ ! -d "$busybox_version" ]; then
        prompt "Extracting busybox"
        tar xf "$busybox_version".tar.bz2
        prompt "Busybox extracted"
    else
        prompt "Busybox already downloaded and extracted"
    fi
}

function choose_syslinux_version() {
    if [ -z $SYSLINUX_VERSION ]; then
        SYSLINUX_VERSION=$(curl -s "$SYSLINUX_BASE_URL" | grep -Eo 'syslinux\-[0-9]\.[0-9]{2}\.tar\.gz' | uniq | tac | fzf)
	response_prompt "$SYSLINUX_VERSION"
    else #we already have the default version at the top of this file
        if [ ! -f "$SYSLINUX_VERSION" ]; then
            prompt "Downloading syslinux"
            wget "$SYSLINUX_BASE_URL""$SYSLINUX_VERSION"
        fi

        if [ ! -d $(echo "$SYSLINUX_VERSION" | sed 's|.tar.gz||g') ]; then

            prompt "Extracting syslinux"
            tar xf "$SYSLINUX_VERSION"
        fi
        prompt "Syslinux downloaded and extracted"
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
    if [ -e _install ]; then
        rm -rf _install
    fi
    make clean
    yes | make mrproper defconfig
    sed -i "s|.*CONFIG_STATIC.*|CONFIG_STATIC=y|" .config
    sed -i "s|.*CONFIG_TC.*|# CONFIG_TC is not set|" .config
    sed -i "s|.*CONFIG_FEATURE_TC_INGRESS.*|# CONFIG_FEATURE_TC_INGRESS is not set|" .config
    sed -i "s|.*CONFIG_FEATURE_IPV6.*|# CONFIG_FEATURE_IPV6 is not set|" .config
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
    prompt "Starting kernel configuration"
    cd "$topdir/$linux_version"
    prompt "Starting kernel compilation"
    case $KERNEL_CONFIG in
        defconfig*)  make_defconfig                  ;;
        modconfig*)  make_modconfig; install_modules ;;
        builtin*)    make_builtin                    ;;
        current*)    make_current; install_modules   ;;
    esac        
    cp arch/x86/boot/bzImage "$topdir"/isoimage/kernel.gz
    cd "$topdir"/isoimage
    cp "$topdir"/$(echo "${SYSLINUX_VERSION}" | sed 's|.tar.gz||g')/bios/core/isolinux.bin .
    cp "$topdir"/$(echo "${SYSLINUX_VERSION}" | sed 's|.tar.gz||g')/bios/com32/elflink/ldlinux/ldlinux.c32 .
    echo 'default kernel.gz initrd=rootfs.gz console=ttyS0 loglevel=9' > isolinux.cfg
}
function make_defconfig() { yes '' | make mrproper ARCH=x86_64 defconfig bzImage -j$(nproc); }
function make_modconfig() { yes '' | make mrproper localmodconfig bzImage modules -j$(nproc); }
function make_builtin() { yes '' | make mrproper localyesconfig bzImage -j$(nproc);  }
function make_current() { get_current_config;  yes '' | make bzImage modules -j$(nproc); }
function get_current_config() {
    local kernel_version=$(uname -r)
    # Remove any color or other bashisms
    # https://stackoverflow.com/a/18000433
    local config_file=$(ls /boot | grep --color=never "$kernel_version" | grep --color=never config)
    cp /boot/"$config_file" .config
}

function install_modules() { make -j$(nproc) INSTALL_MOD_PATH="$topdir"/"$busybox_version"/_install modules_install; }

function dvorak_setting() {
    if [ '$DVORAK' == 'yes' ]; then 
       mkdir -p "$topdir"/overlay/usr/share/kmaps
       cp "$topdir"/dvorak.kmap "$topdir"/overlay/usr/share/kmaps
       sed -i 's|setsid cttyhack /bin/sh|loadkmap < /usr/share/kmaps/dvorak.kmap\nsetsid cttyhack /bin/sh|g' "$topdir"/"$busybox_version"/_install/init
    fi
}

function apply_overlay() {
    cp -a "$overlay/" "$topdir"/"${busybox_version}"/_install
}

function compress_initrd() {
    cd "$topdir"/"${busybox_version}"/_install && find . | cpio -R root:root -H newc -o | gzip > "$topdir"/isoimage/rootfs.gz
    cd -
}

function copy_firmware() {
    # find all the files which have been accessed since boot
    # https://stackoverflow.com/a/13385076
    days_uptime=$(uptime | grep -Eo --color=never '[0-9]+ days' | sed 's|days||g' | sed 's| ||g')
    if [ -z "$days_uptime" ]; then
        days_uptime=1
    fi
    cd "$topdir"
    find /lib/firmware -depth -print -atime "$days_uptime" | cpio -pvd overlay
}

function make_iso() {
    cd "$topdir"/isoimage
    xorriso \
        -as mkisofs \
        -o ../tinylinux.iso \
        -b isolinux.bin \
        -c boot.cat \
        -no-emul-boot \
        -boot-load-size 4 \
        -boot-info-table \
    ./
    cd "$topdir"
}

function wget() { $(realpath $(which wget)) "$@" -q --show-progress; }
function current_terminal_height() { echo -ne "$LINES"; }
function fzf() { ./fzf -d $(($(current_terminal_height) - 5))  --height 40% --layout=reverse ; }
function prompt() { color_print green bold  "$@" ;}
function response_prompt() { color_print orange bold "You chose $@"; }

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
KERNEL_BASE_URL=https://mirrors.edge.kernel.org/pub/linux/kernel/
SYSLINUX_BASE_URL=https://mirrors.edge.kernel.org/pub/linux/utils/boot/syslinux/
PATCH_BASE_URL=https://mirrors.edge.kernel.org/pub/linux/kernel/projects/rt/
BUSYBOX_BASE_URL=https://busybox.net/downloads/

main "$@"
