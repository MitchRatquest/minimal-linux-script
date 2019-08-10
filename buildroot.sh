#!/bin/bash

function main() {
	get_buildroot
	set_configurations

}

function get_buildroot() {
	commit=9b9abb0dd03114347d10d09131ad4e96f5583514
	git clone https://github.com/buildroot/buildroot.git
	cd buildroot
	git checkout "$commit"
	cd ..
}

function set_configurations() {
	make O=$PWD buildroot/ defconfig BR2_DEFCONFIG=br_defconfig
}
