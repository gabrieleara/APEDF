#!/bin/bash

function print_list() {
	while [ $# -gt 0 ]; do
		echo '-' "$1"
		shift
	done
}

function usage() {
	cat <<EOF
USAGE:  $SCRIPT_NAME BASE_OUTPUT_DIRECTORY

BASE_OUTPUT_DIRECTORY must be a valid directory containing the output of a
testset execution.
It must contain one sub-folder for each scheduler variant, each with a subfolder
for each schedutil governor.

Supported scheduler variants:
$(print_list "${SCHEDULERS[@]}")

Supported governors:
$(print_list "${GOVERNORS[@]}")

EOF
}

function main() {
	SCRIPT_PATH="$(realpath "${BASH_SOURCE[0]}")"
	SCRIPT_NAME="$(basename "${BASH_SOURCE[0]}")"
	SCRIPT_DIR="$(realpath "$(dirname "$SCRIPT_PATH")")"
	COLLECT_PY=$(realpath "$SCRIPT_DIR/scripts/collection/collect.py")

	SCHEDULERS=(global apedf-ff apedf-wf)
	GOVERNORS=(performance schedutil)

	if [ $# -lt 1 ]; then
		usage >&2
		return 1
	fi

	TEST_OUTDIR="$1"
	if [ ! -d "$TEST_OUTDIR" ]; then
		echo "ERROR: argument '$1' is not a valid directory!" >&2
		usage >&2
		return 1
	fi

	for scheduler in "${SCHEDULERS[@]}"; do
		for governor in "${GOVERNORS[@]}"; do
			curdir="$TEST_OUTDIR/$scheduler/$governor"

			echo -n " - Checking for '$curdir': "
			if ! [ -d "$curdir" ]; then
				echo "not found, skipping..."
				continue
			fi

			echo "found, collecting data..."
			"$COLLECT_PY" \
				-o "$1/$scheduler/tsets-$governor.csv" \
				-O "$1/$scheduler/tasks-$governor.csv" \
				-m \
				-D "$curdir"
		done
	done

	echo " == DONE == "
}

(
	set -e
	main "$@"
)
