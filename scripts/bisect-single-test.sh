#!/bin/bash

function main() {
	cd "$(realpath "$(dirname "$(realpath "${BASH_SOURCE[0]}")")"/..)"

	rm -rf bisect-out
	mkdir bisect-out

	./scripts/tasks-run.sh \
		--skipbuild \
		--printlist \
		--timeout 90 \
		--cooldown 30 \
		--tasksdir "./in" \
		--outdir "./bisect-out/performance" \
		--governor "performance" \
		--corelist 4-7 \
		--turnoff "0 1 2 3" \
		--maxfreq 1.4GHz

	sleep 30s

	./scripts/tasks-run.sh \
		--skipbuild \
		--printlist \
		--timeout 90 \
		--cooldown 30 \
		--tasksdir "./in" \
		--outdir "./bisect-out/schedutil" \
		--governor "schedutil" \
		--corelist 4-7 \
		--turnoff "0 1 2 3" \
		--maxfreq 1.4GHz

	sleep 30s
}

(
	set -e
	main "$@"
)
