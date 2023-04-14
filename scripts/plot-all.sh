#!/bin/bash

main() {
	for s in global apedf apedfwf; do
		for g in performance schedutil; do
			if ! [ -f "$1/$s/tsets-$g.csv" ] ; then
				continue
			fi
			./scripts/plot.py -o "$1/$s/$g.png" "$1/$s/tsets-$g.csv"
			./scripts/plot-freq.py -o "$1/$s/$g-freq.png" "$1/$s/tasks-$g.csv"
		done
	done
}

(
	set -e
	main "$@"
)
