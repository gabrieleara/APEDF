#!/bin/bash

function run_ntasks_with_governor() {
	local ntasks="$1"
	local governor="$2"

	echo "#================================================================#"
	echo "#"
	echo "#          STARTING BLOCK $1 $2"
	echo "#"
	echo "#================================================================#"

	./scripts/tasks-run.sh \
		--skipbuild \
		--printlist \
		--timeout 90 \
		--cooldown 30 \
		--tasksdir "./tasksets/$ntasks" \
		--outdir "out/$governor" \
		--governor "$governor" \
		--corelist 4-7 \
		--turnoff "0 1 2 3" \
		--maxfreq 1.4GHz
}

function ntasks_list() {
	(
		set -e
		cd ./tasksets
		for d in *; do
			if [ -d $d ]; then echo $d; fi
		done | sort -n
	)
}

function main() {
	SCRIPT_DIR="$(realpath "$(dirname "${BASH_SOURCE[0]}")")"
	APEDF_DIR="$(realpath "$SCRIPT_DIR/..")"

	cd "$APEDF_DIR"

	for ntasks in 06 08 12 16; do
		run_ntasks_with_governor "$ntasks" performance
		run_ntasks_with_governor "$ntasks" schedutil
	done

	echo "++++++++++ END OF EXPERIMENTS MARKER ++++++++++"
}

(
	set -e
	main "$@"
)
