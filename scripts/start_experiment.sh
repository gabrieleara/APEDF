#!/bin/bash

function main() {
	SCRIPT_DIR="$(realpath "$(dirname "${BASH_SOURCE[0]}")")"
	APEDF_DIR="$(realpath "$SCRIPT_DIR/..")"

	cd "$APEDF_DIR"

	# Turn off unwanted CPUs
	for c in 0 1 2 3; do
		echo 0 >/sys/devices/system/cpu/cpu$c/online
	done

	# Just in case
	cpufreq-set -c4 -f1.4GHz

	# Check that everything is as it should be
	sleep 2s
	for c in 0 1 2 3; do
		online=$(cat /sys/devices/system/cpu/cpu$c/online)
		if [ "$online" = 1 ]; then
			echo "COULD NOT TURN CPU $c OFFLINE!!" >&2
			return 1
		fi
	done

	# Start experiment in a detached screen named "experiment"
	screen -L -Logfile last_experiment.log \
		-S experiment \
		-d -m \
		./scripts/tasks-run.sh \
		--skipbuild \
		--printlist \
		--cooldown 90 \
		--maxfreq=1.4GHz \
		--tasksdir=./tasksets/

	return 0
}

(
	set -e
	main "$@"
)
