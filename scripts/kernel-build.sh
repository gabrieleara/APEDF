#!/bin/bash

usage() {
	echo "
Usage: ${SCRIPT_NAME} <options>

    --srcdir=PATH       - kernel source directory (default: current directory)
    --target=TARGET     - work with a kernel for TARGET (see below the list of
                          supported targets)
    --config=CONFIG     - use provided configuration (see below for the list of
                          supported configurations)

    -h --help           - show this help message and exit
    --debug             - run this program in debug mode

THIS SCRIPT AUTOMATICALLY DETECTS WHETHER CROSS COMPILATION IS REQUIRED.

SUPPORTED TARGETS: rpi4, odroidxu4

SUPPORTED CONFIGURATIONS:
    - noconfig          - skip configuration step [DEFAULT]
    - defconfig         - use default configuration for the selected target (or if no target
                          is supplied use 'defconfig')
    - oldconfig         - use 'oldconfig' to rerun configuration
    - ANY OTHER VALUE   - forward the value as is to the kernel build system

"
}

parse_args() {
	SRCDIR=.
	TARGET=
	CONFIG=
	CROSS_COMPILING=n
	MAKETARGETS=()
	CROSS_COMPILE_OPTIONS=()
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
		--config*)
			if echo $1 | grep '=' >/dev/null; then
				CONFIG=$(echo $1 | sed 's/^--config=//')
			elif [ -n "$2" ]; then
				CONFIG=$2
				shift
			else
				echo "${SCRIPT_NAME}: Error - '--config' expects an argument"
				usage
				return 1
			fi
			;;
		*)
			echo "${SCRIPT_NAME}: Error - ${1}"
			usage
			exit 1
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
	rpi4)
		MAKETARGETS=(Image.gz modules dtbs)
		;;
	odroidxu4) ;;
	notarget) ;;
	*)
		echo "${SCRIPT_NAME}: Error - supplied target '$TARGET' is not supported!"
		usage
		return 1
		;;
	esac
}

adjust_config() {
	if [ "$CONFIG" != defconfig ]; then
		return 0
	fi

	case "$TARGET" in
	rpi4)
		KERNEL=kernel8
		export KERNEL
		CONFIG=bcm2711_defconfig
		;;
	odroidxu4)
		CONFIG=odroidxu4_defconfig
		;;
	*) ;;
	esac
}

cross_compile_arm64() {
	# TODO
	CROSS_COMPILE_OPTIONS=(ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu-)
}

cross_compile_arm() {
	# TODO
	CROSS_COMPILE_OPTIONS=(ARCH=arm CROSS_COMPILE=arm-linux-gnueabihf-)
}

check_cross_compilation() {
	case "$TARGET" in
	rpi4)
		# Arch must be arm64
		if [ "$(uname -m)" != aarch64 ]; then
			# Cross compilation is required
			CROSS_COMPILING=y
			cross_compile_arm64
		fi
		;;
	odroidxu4)
		# Arch must be armv7
		if [ "$(uname -m)" != armv7l ]; then
			# Cross compilation is required
			CROSS_COMPILING=y
			cross_compile_arm
		fi
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

build_run() {
	if [ -n "$CONFIG" ] && [ "$CONFIG" != noconfig ]; then
		# Configure
		make "${CROSS_COMPILE_OPTIONS[@]}" "$CONFIG"
	fi

	make \
		"${CROSS_COMPILE_OPTIONS[@]}" \
		-j $(($(nproc) * 6 / 8)) \
		"${MAKETARGETS[@]}"
}

cleanup() {
	:
}

main() {
	SCRIPT_NAME="$(basename "$0")"

	parse_args "$@"
	check_target_supported
	adjust_config
	check_cross_compilation
	check_srcdir

	echo ""
	echo "============================================================"
	echo ""
	echo " Configuration: "
	echo " => SOURCE DIR     $SRCDIR"
	echo " => TARGET         $TARGET"
	echo " => CONFIG         $CONFIG"
	echo " => MAKETARGETS    ${MAKETARGETS[@]}"
	echo " => CROSS COMPILE  $CROSS_COMPILING"
	echo " => CROSS OPTIONS  ${CROSS_COMPILE_OPTIONS[@]}"
	echo ""
	echo "============================================================"
	echo ""

	cd "$SRCDIR"

	# Perform the installation for the known target
	build_run
	sync
	cleanup

	echo ""
	echo " KERNEL BUILD SUCCESSFULLY!"
	echo ""
}

(
	set -e
	main "$@"
)
