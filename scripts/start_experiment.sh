#!/bin/bash

function main() {
	SCRIPT_DIR="$(realpath "$(dirname "${BASH_SOURCE[0]}")")"
	APEDF_DIR="$(realpath "$SCRIPT_DIR/..")"

	cd "$APEDF_DIR"

	# # Turn off unwanted CPUs
	# for c in 0 1 2 3; do
	# 	echo 0 >/sys/devices/system/cpu/cpu$c/online
	# done
	# Just in case
	# cpufreq-set -c4 -f1.4GHz
	# # Check that everything is as it should be
	# sleep 2s
	# for c in 0 1 2 3; do
	# 	online=$(cat /sys/devices/system/cpu/cpu$c/online)
	# 	if [ "$online" = 1 ]; then
	# 		echo "COULD NOT TURN CPU $c OFFLINE!!" >&2
	# 		return 1
	# 	fi
	# done

	# Check that there are no screens named 'experiment' around
	if screen -ls | cut -d. -f2 | tail -n +2 | cut -d$'\t' -f1 | grep -q experiment; then
		echo "An experiment is already running (screen open)!" >&2
		return 1
	fi

	# Check that the experiment script is running
	if pgrep multiple-experiment-wrapper.sh >/dev/null; then
		echo "An experiment is already running!" >&2
		return 1
	fi

	# Start experiment in a detached screen named "experiment"
	screen -L -Logfile last_experiment.log \
		-S experiment \
		-d -m \
		./scripts/multiple-experiment-wrapper.sh

	return 0
}

(
	set -e
	main "$@"
)
