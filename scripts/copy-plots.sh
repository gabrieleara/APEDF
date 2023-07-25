#!/bin/bash

function main() {
	local indir="$1"
	local outdir="$2"
	local infile
	local outfile

	if ! [ -d "$indir" ] || ! [ -d "$outdir" ]; then
		echo "usage: ${BASH_SOURCE[0]} INDIR OUTDIR" >&2
		return 1
	fi

	for FORMAT in png svg; do
		for governor in performance schedutil; do
			for dimen in freq-lines miss-lines miss-lines-log ; do
				for plot_type in min max mean q20 q50 q90; do
					cp $indir/multi/$governor.$dimen.$plot_type.$FORMAT $outdir/multi.$governor.$dimen.$plot_type.$FORMAT || true
				done
			done
		done

		for scheduler in global apedf apedfwf; do
			for governor in performance schedutil; do
				for plot_type in abs ratio freq.mean freq.min freq.max migr-abs migr-ratio; do
					cp $indir/$scheduler/$governor.$plot_type.$FORMAT $outdir/$scheduler.$governor.$plot_type.$FORMAT || true
				done

			done
		done
	done
}

(
	set -e
	main "$@"
)
