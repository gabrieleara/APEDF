#!/bin/bash

main() {
	for s in global apedf; do
		for g in performance schedutil; do
			if ! [ -d "$1/$s" ] ; then
				continue
			fi
		./scripts/plot.py -o "$1/$s/$g.png" "$1/$s/tsets-$g.csv"
		done
	done
}

(
	set -e
	main "$@"
)
