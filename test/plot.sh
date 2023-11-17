#!/bin/bash

main() {
	odir_multi="$1/multi"
	mkdir -p "$odir_multi"

	for FORMAT in png svg; do
		for g in performance schedutil; do
			./scripts/plot-multi.py -O "$FORMAT" -o "$odir_multi/$g"  \
				"$1"/apedf-ff/tasks-$g.csv \
				"$1"/apedf-wf/tasks-$g.csv \
				"$1"/global/tasks-$g.csv \
				"$1"/apedf-ff/tsets-$g.csv \
				"$1"/apedf-wf/tsets-$g.csv \
				"$1"/global/tsets-$g.csv \
				|| true
		done

		for s in global apedf-ff apedf-wf; do
			for g in performance schedutil; do
				if ! [ -f "$1/$s/tsets-$g.csv" ]; then
					continue
				fi
				./scripts/plot.py -O "$FORMAT" -o "$1/$s/$g" "$1/$s/tsets-$g.csv" "$1/$s/tasks-$g.csv"
			done
		done
	done
}

(
	set -e
	main "$@"
)
