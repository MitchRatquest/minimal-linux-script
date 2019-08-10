#!/bin/bash

function main() {
	get_buildroot
	set_configurations
	create_overlay
	populate_overlay
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

function set_configurations() {
	if [ ! -f .initial_br ]; then
		make O=$PWD -C buildroot/ defconfig BR2_DEFCONFIG=br_defconfig
	fi
}

function create_ovelay() {
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

main "$@"