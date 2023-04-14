#!/bin/bash

main() {
	for s in global apedf apedfwf; do
		for g in performance schedutil; do
			if ! [ -d "$1/$s" ] ; then
				continue
			fi

			./scripts/collect.py -o "$1/$s/tsets-$g.csv" -O "$1/$s/tasks-$g.csv" -m -D "$1/$s/$g"
		done
	done
}

(
	set -e
	main "$@"
)
