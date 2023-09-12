#!/bin/bash

usage() {
	echo "
Usage: ${SCRIPT_NAME} <options>

    --srcdir=PATH       - kernel source directory (default: current directory)
    --remote=REMOTE     - install on the remote host (requires sshfs)
    --target=TARGET     - work with a kernel for TARGET (see below the list of
                          supported targets)

    --skip-modules      - skips the step of installing the kernel modules

    -h --help           - show this help message and exit
    --debug             - run this program in debug mode


SUPPORTED TARGETS: rpi4, odroidxu4

"
}

parse_args() {
	SRCDIR=.
	REMOTE=
	TARGET=
	SKIP_MODULES=n
	while [ $# -gt 0 ]; do
		case $1 in
		--debug)
			set -x
			;;
		-h | --help)
			usage
			return 1
			;;
		--srcdir*)
			if echo $1 | grep '=' >/dev/null; then
				SRCDIR=$(echo $1 | sed 's/^--srcdir=//')
			elif [ -n "$2" ]; then
				SRCDIR=$2
				shift
			else
				echo "${SCRIPT_NAME}: Error - '--srcdir' expects an argument"
				usage
				return 1
			fi
			;;
		--remote*)
			if echo $1 | grep '=' >/dev/null; then
				REMOTE=$(echo $1 | sed 's/^--remote=//')
			elif [ -n "$2" ]; then
				REMOTE=$2
				shift
			else
				echo "${SCRIPT_NAME}: Error - '--remote' expects an argument"
				usage
				return 1
			fi
			;;
		--target*)
			if echo $1 | grep '=' >/dev/null; then
				TARGET=$(echo $1 | sed 's/^--target=//')
			elif [ -n "$2" ]; then
				TARGET=$2
				shift
			else
				echo "${SCRIPT_NAME}: Error - '--target' expects an argument"
				usage
				return 1
			fi
			;;
		--skip-modules)
			SKIP_MODULES=y
			;;
		*)
			echo "${SCRIPT_NAME}: Error - ${1}"
			usage
			return 1
			;;
		esac
		shift
	done
}

check_target_supported() {
	if [ -z "$TARGET" ]; then
		echo "${SCRIPT_NAME}: Error - the '--target' is a required option!"
		usage
		return 1
	fi

	case "$TARGET" in
	rpi4) ;;
	odroidxu4) ;;
	*)
		echo "${SCRIPT_NAME}: Error - supplied target '$TARGET' is not supported!"
		usage
		return 1
		;;
	esac
}

check_srcdir() {
	if ! [ -d "$SRCDIR" ]; then
		echo "${SCRIPT_NAME}: Error - '$SRCDIR' is not a valid directory!"
		usage
		return 1
	fi

	# TODO: test also that the current directory contains a valid built kernel maybe
}

install_rpi4() {
	# NOTE: assumes arm64

	KERNEL=kernel8
	export KERNEL

	if [ "$SKIP_MODULES" != y ]; then
		make modules_install INSTALL_MOD_PATH="$DEST_DIR"
	fi

	cp arch/arm64/boot/dts/broadcom/*.dtb "$DEST_DIR/"boot/
	cp arch/arm64/boot/dts/overlays/*.dtb* "$DEST_DIR/"boot/overlays/
	cp arch/arm64/boot/dts/overlays/README "$DEST_DIR/"boot/overlays/
	cp arch/arm64/boot/Image.gz "$DEST_DIR/"boot/$KERNEL.img
}

install_odroidxu4() {
	# NOTE: assumes armv7

	if [ "$SKIP_MODULES" != y ]; then
		make modules_install INSTALL_MOD_PATH="$DEST_DIR"
	fi

	cp -f arch/arm/boot/dts/exynos5422-odroidxu3.dtb	"$DEST_DIR"/media/boot
	cp -f arch/arm/boot/dts/exynos5422-odroidxu4.dtb	"$DEST_DIR"/media/boot
	cp -f arch/arm/boot/dts/exynos5422-odroidxu3-lite.dtb	"$DEST_DIR"/media/boot
	cp -f arch/arm/boot/zImage				"$DEST_DIR"/media/boot
}

cleanup() {
	if [ -n $DEST_DIR ] && [ -d "$DEST_DIR" ]; then
		if umount "$DEST_DIR"; then
			rmdir "$DEST_DIR"
		else
			echo "${SCRIPT_NAME}: Error - please umount and remove the $DEST_DIR  directory manually..."
		fi

		DEST_DIR=
	fi
}

main() {
	SCRIPT_NAME="$(basename "$0")"

	parse_args "$@"
	check_target_supported
	check_srcdir

	DEST_DIR=/

	if [ "$REMOTE" != '' ]; then
		DEST_DIR=$(mktemp -d)
		echo " Connecting to selected remote..."
		echo ""
		echo " You might be prompted for the password to log into the"
		echo " selected remote now..."
		echo ""
		echo " NOTE - remote user must be able to write to root protected"
		echo " directories! Suggest logging as root to begin with."
		echo ""
		sshfs "$REMOTE":/ "$DEST_DIR"
	fi

	if [ "$DEST_DIR" = / ]; then
		echo ""
		echo " ***********************************************************"
		echo " **                        WARNING                        **"
		echo " **                                                       **"
		echo " ** You have requested to overwrite the kernel in /boot   **"
		echo " ** of the current machine.                               **"
		echo " **                                                       **"
		echo " ** Do you wish to continue? (type 'yes' to continue)     **"
		echo " **                                                       **"
		echo " ***********************************************************"

		# wait for agreement
		printf " = Continue? "
		local AGREE
		read AGREE
		if [ "$(echo ${AGREE} | tr '[:lower:]' '[:upper:]')" != "YES" ]; then
			echo "User exit, no kernel written."
			return 0
		fi
	fi

	DEST_DIR=$(realpath "$DEST_DIR")

	echo ""
	echo "============================================================"
	echo ""
	echo " Configuration: "
	echo " => SOURCE DIR     $SRCDIR"
	echo " => TARGET         $TARGET"
	echo " => REMOTE         $REMOTE"
	echo " => SKIP MODULES   $SKIP_MODULES"
	echo ""
	echo "============================================================"
	echo ""

	cd "$SRCDIR"

	# Perform the installation for the known target
	"install_$TARGET"
	sync
	cleanup

	echo ""
	echo " INSTALLED!"
	echo ""
}

(
	set -e
	main "$@"
)
