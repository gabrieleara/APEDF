#!/bin/bash

function run_ntasks_with_governor() {
	local ntasks="$1"
	local outdir="$2"
	local governor="$3"

	echo "#================================================================#"
	echo "#"
	echo "#          STARTING BLOCK $1 $2 $3"
	echo "#"
	echo "#================================================================#"

	./scripts/tasks-run.sh \
		--skipbuild \
		--printlist \
		--timeout 90 \
		--cooldown 30 \
		--tasksdir "./tasksets/$ntasks" \
		--outdir "$outdir/$governor" \
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

	PLACEMENT=global
	if uname -a | grep apedf >/dev/null 2>&1 ; then
		if uname -a | grep wf >/dev/null 2>&1 ; then
			PLACEMENT=apedf-wf
		else
			PLACEMENT=apedf-ff
		fi
	fi

	cd "$APEDF_DIR"

	OUTDIR=out/$PLACEMENT

	for ntasks in 16 12 08 06 ; do
		run_ntasks_with_governor "$ntasks" "$OUTDIR" performance
		run_ntasks_with_governor "$ntasks" "$OUTDIR" schedutil
	done

	echo "++++++++++ END OF EXPERIMENTS MARKER ++++++++++"
}

(
	set -e
	main "$@"
)
