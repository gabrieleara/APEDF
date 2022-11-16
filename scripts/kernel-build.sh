#!/bin/bash

# Arguments of this script:
#  1. The directory where to find the kernel to run
#  2. Either the word 'defconfig' or 'oldconfig' or 'noconfig'
#     [default=noconfig]
#  3. The kernel version to test, based on the git tag [optional, default=no
#     checkout will be performed and it will use the tree as is]
#
# NOTE: run this on the board, because on another machine it may not
# generate the final zImage

function main() {
	DEFCONFIG=odroidxu4_defconfig

	if [ $# -lt 1 ]; then
		echo "USAGE: ${BASH_SOURCE[0]} LINUX_KERNEL_PATH [CONFIG] [GIT_BRANCH_OR_TAG]" >&2
		return 1
	fi

	LINUX_PATH="$1"
	CONFIG="${2:-noconfig}"
	BRANCH_OR_TAG="$3"

	cd "$LINUX_PATH"
	if [ -n "$BRANCH_OR_TAG" ]; then
		git checkout "$BRANCH_OR_TAG"
	fi

	case "$CONFIG" in
	defconfig)
		make "$DEFCONFIG"
		;;
	oldconfig)
		make oldconfig
		;;
	noconfig)
		;;
	*)
		echo "Unexpected config supplied!" >&2
		return 1
		;;
	esac

	# Compile
	make -j $(($(nproc) * 6 / 8))
}

(
	set -e

	# export ARCH=arm
	# export CROSS_COMPILE=arm-linux-gnueabi-

	export ARCH=arm
	export CROSS_COMPILE=arm-linux-gnu-

	main "$@"
)
