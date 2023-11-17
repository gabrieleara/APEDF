#!/bin/bash

GIT_BISECT_UGLY=5.4.227-409 # apedf-ugly # tag: 5.4.227-409
GIT_BISECT_NICE=5.4.236-414 # apedf-nice # tag: 5.4.236-414

function start() {
	cd_dir
	git checkout "$GIT_BISECT_NICE"
	git bisect start --term-old=ugly --term-new=nice
	git bisect nice
	git bisect ugly "$GIT_BISECT_UGLY"
	git bisect run "$SCRIPT_DIR/bisect-step.sh"
}

function resume() {
	echo "NOT SUPPORTED YET!"
	return 1
}

function usage() {
	echo "USAGE: $0 [start|resume]" >&2
	return 1
}

function main() {
	if [ $# -lt 1 ]; then
		usage
	fi

	if [ $# -gt 1 ]; then
		usage
	fi

	case "$1" in
	start)
		start
		;;
	resume)
		step "$1"
		;;
	*)
		usage
		;;
	esac
}

(
	set -e
	main "$@"
)
