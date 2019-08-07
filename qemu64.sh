#!/bin/sh
qemu-system-x86_64 -m 128M -cdrom minimal_linux_live.iso -boot d  -smp 4 -nographic  -serial mon:stdio  -no-reboot -enable-kvm -cpu host -device e1000
#qemu-system-x86_64 -m 128M -cdrom minimal_linux_live.iso -boot d -vga std

