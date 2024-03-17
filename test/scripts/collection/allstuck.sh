#!/bin/bash

PARALLEL=1

function main() {
	. $(which env_parallel.bash)

#	env_parallel --record-env

	SCRIPT_DIR="$(realpath "$(dirname "$(realpath "${BASH_SOURCE[0]}")")")"
	POWERSTUCK="$SCRIPT_DIR/powerstuck.awk"

	ARGPATH=.

	if [ -n "$1" ] ; then
		ARGPATH="$1"
	fi

	if ! [ -e "$ARGPATH" ]; then
		echo "$ARGPATH does not exist!" >&2
		return 1
	fi

	function dowork() {
		local f="$1"
		echo -n "file $f "
		tail -n +2 "$f" | "$POWERSTUCK" -F,
	}

#	find "$ARGPATH" -name power.log | env_parallel --env _ dowork
	export -f dowork
	export POWERSTUCK
	find "$ARGPATH" -name power.log | env_parallel dowork

}

(
	set -e
	main "$@"
)
