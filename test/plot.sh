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
testset execution together with data collected using the 'collect.sh' utility.
For more info see '$COLLECT_SH'.

Similarly to the 'collect.sh' utility, this script only supports a fixed set of
scheduler variants and schedutil governors.

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

	COLLECT_SH="$(realpath "$SCRIPT_DIR/collect.sh")"
	VISUALIZATION_DIR="$(realpath "$SCRIPT_DIR/scripts/visualization")"

	PLOT_MULTI_PY="$(realpath "$VISUALIZATION_DIR/plot-multi.py")"
	# PLOT_FREQ_PY="$(realpath "$VISUALIZATION_DIR/plot-freq.py")"
	PLOT_PY="$(realpath "$VISUALIZATION_DIR/plot.py")"

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

	odir_multi="$TEST_OUTDIR/multi"
	mkdir -p "$odir_multi"

	for FORMAT in png svg; do
		for governor in "${GOVERNORS[@]}"; do
			echo "Plotting data to '$odir_multi/$governor' in $FORMAT format..."
			"$PLOT_MULTI_PY" \
				-O "$FORMAT" \
				-o "$odir_multi/$governor"  \
				"${TEST_OUTDIR}/apedf-ff/tasks-${governor}.csv" \
				"${TEST_OUTDIR}/apedf-wf/tasks-${governor}.csv" \
				"${TEST_OUTDIR}/global/tasks-${governor}.csv" \
				"${TEST_OUTDIR}/apedf-ff/tsets-${governor}.csv" \
				"${TEST_OUTDIR}/apedf-wf/tsets-${governor}.csv" \
				"${TEST_OUTDIR}/global/tsets-${governor}.csv" \
				|| true
		done

		for scheduler in "${SCHEDULERS[@]}"; do
			for governor in "${GOVERNORS[@]}"; do
				infile="${TEST_OUTDIR}/${scheduler}/tsets-${governor}.csv"
				echo -n "- Checking for $infile: "
				if ! [ -f "${TEST_OUTDIR}/$scheduler/tsets-$governor.csv" ]; then
					echo "not found, skipping..."
					continue
				fi

				echo "found, generating plots in $FORMAT format..."
				"$PLOT_PY" \
					-O "$FORMAT" \
					-o "${TEST_OUTDIR}/$scheduler/$governor" \
					"${TEST_OUTDIR}/$scheduler/tsets-$governor.csv" \
					"${TEST_OUTDIR}/$scheduler/tasks-$governor.csv"
			done
		done
	done

	echo " == DONE == "
}

(
	set -e
	main "$@"
)
