#!/bin/bash
if [[ $1 != 'fast' ]]; then
	qemu-system-x86_64 -m 128M -cdrom tinylinux.iso -boot d -vga std -smp 4 -device e1000
else
	sudo qemu-system-x86_64 -m 128M -cdrom tinylinux.iso -boot d  -smp 4 -nographic  -serial mon:stdio  -no-reboot -enable-kvm -cpu host -device e1000
fi

