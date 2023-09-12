#!/bin/bash

main() {
	for s in global apedf apedfwf; do
		for g in performance schedutil; do
			if ! [ -f "$1/$s/tsets-$g.csv" ] ; then
				continue
			fi
			./scripts/plot-dhall.py -o "$1/$s/$g-dhall.png" "$1/$s/tasks-$g.csv"
		done
	done
}

(
	set -e
	main "$@"
)
