#!/bin/bash

EXTRA_PACKAGES=(gcc bash)
USE_EXTERNAL_GCC=no

function main() {
	get_buildroot
	set_configurations
	get_external_toolchain
	create_overlay
	populate_overlay
	install_extras
	make -j$(nproc)
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

function get_external_toolchain() {
	if [ "$USE_EXTERNAL_GCC" == 'yes' ]; then
		if [ ! -f static-get ]; then
			wget https://raw.githubusercontent.com/minos-org/minos-static/master/static-get
			chmod 777 static-get
		fi
		mkdir external_toolchain
		cd external_toolchain
		../static-get -x gcc #needs to be >= 4.6.0 for linux >= 4.19 https://git.kernel.org/pub/scm/linux/kernel/git/torvalds/linux.git/commit/?id=cafa0010cd51fb711fdcb50fc55f394c5f167a0a
#• Use a completely custom external toolchain. This is particularly useful for toolchains generated using crosstool-NG or with
#Buildroot itself. To do this, select the Custom toolchain solution in the Toolchain list. You need to fill the Toolch
#ain path, Toolchain prefix and External toolchain C library options. Then, you have to tell Buildroot
#what your external toolchain supports. If your external toolchain uses the glibc library, you only have to tell whether your
#toolchain supports C++ or not and whether it has built-in RPC support. If your external toolchain uses the uClibc library, then
#you have to tell Buildroot if it supports RPC, wide-char, locale, program invocation, threads and C++. At the beginning of the
#execution, Buildroot will tell you if the selected options do not match the toolchain configuration.
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
	mkdir -p overlay/etc/init.d
	cp dvorak.kmap overlay/usr/share/kmaps/dvorak.kmap
	echo -ne > overlay/etc/init.d/S99-dvorak
	cat >> overlay/etc/init.d/S99-dvorak << EOF
#!/bin/sh
loadkmap < /usr/share/kmaps/dvorak.kmap
exit 0
EOF
	chmod 777 overlay/etc/init.d/S99-dvorak
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

main "$@"