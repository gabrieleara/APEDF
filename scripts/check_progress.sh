#!/bin/bash

function trim() {
	xargs
}

function main() {
	SCRIPT_DIR="$(realpath "$(dirname "${BASH_SOURCE[0]}")")"
	APEDF_DIR="$(realpath "$SCRIPT_DIR/..")"

	cd "$APEDF_DIR"

	PROGRESS_FILE="last_experiment.log"
	TMP_FILE=$(mktemp)

	# Check that the experiment script is running
	if pgrep tasks-run.sh >/dev/null; then
		running=1
	else
		running=0
	fi

	# Log file in reverse
	tac "$PROGRESS_FILE" >"$TMP_FILE"

	# Get first NON BLANK line
	line=""
	while read line; do
		line=$(echo "$line" | trim)
		if [ -n "$line" ] && ! (echo "$line" | grep -q 'command not found'); then
			break
		fi
	done <"$TMP_FILE"
	if [ -z "$line" ]; then
		echo "Empty LOG file??" >&2
		return 1
	fi

	# If this line is shown, it's over
	if echo "$line" | grep -q "All tests successful"; then
		echo 'END'
		return 0
	fi

	# If no process was found before, raise error
	if [ $running = 0 ]; then
		echo "No tasks-run.sh process running" >&2
		return 1
	fi

	# Extract progress
	progress=$(echo "$line" | sed 's/.*\(\[[0-9]\+\/[0-9]\+\]\).*/\1/')
	echo "$progress"
	return 0
}

(
	set -e
	main "$@"
)
