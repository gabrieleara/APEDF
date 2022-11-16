#!/bin/bash

# Arguments of this script:
#  1. The directory where to find the kernel

function main() {
	if [ $# -lt 1 ]; then
		echo "USAGE: ${BASH_SOURCE[0]} LINUX_KERNEL_PATH" >&2
		return 1
	fi

	LINUX_PATH="$1"

	cd "$LINUX_PATH"
	make modules_install
	cp -f arch/arm/boot/zImage /media/boot
	cp -f arch/arm/boot/dts/exynos5422-odroidxu3.dtb /media/boot
	cp -f arch/arm/boot/dts/exynos5422-odroidxu4.dtb /media/boot
	cp -f arch/arm/boot/dts/exynos5422-odroidxu3-lite.dtb /media/boot
	sync

	echo "INSTALLED!"
}

(
	set -e
	main "$@"
)
