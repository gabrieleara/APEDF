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

	for scheduler in global apedf apedfwf; do
		for governor in performance schedutil; do
			for infile_basename in "$governor.abs.png" "$governor.ratio.png" "$governor.freq.png"; do
				cp $indir/$scheduler/$infile_basename $outdir/$scheduler-$infile_basename
			done
		done
	done
}

(
	set -e
	main "$@"
)
