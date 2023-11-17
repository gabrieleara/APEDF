#!/bin/bash

# This script must return:
# - 0 on a good run
# - 1 on a failure
# - 125 on an untestable version (bisect will move to
#   another commit without testing)
# - 128 to abort the bisect

GIT_PATCHES_FIRST=apedf-base
GIT_PATCHES_LAST=apedf-ff

# NOTE: script must be run from within the kernel directory
SCRIPT_DIR="$(realpath "$(dirname "$(realpath "${BASH_SOURCE[0]}")")")"
KERNEL_SRCDIR="$(realpath "$PWD")"
OUT_TEST_DIR="$(realpath "$SCRIPT_DIR"/../bisect-out)"
LAST_BISECT_COMMIT_FILE=$SCRIPT_DIR/.LAST_BISECT_COMMIT

HOST="root@10.30.3.51"

function beep() {
	paplay /usr/share/sounds/freedesktop/stereo/complete.oga
}

function apply-patches() {
	echo "# Applying patches..."
	git rev-parse HEAD >"$LAST_BISECT_COMMIT_FILE"
	git cherry-pick --no-commit "$GIT_PATCHES_FIRST".."$GIT_PATCHES_LAST"

	# Add commit number to the release version
	sed -i 's/\(-apedf2\)/\1-'"$(cat "$LAST_BISECT_COMMIT_FILE")"'/' Makefile
}

function build() {
	echo "# Building the kernel..."
	"$SCRIPT_DIR"/kernel-build.sh --srcdir="$KERNEL_SRCDIR" --target=odroidxu4 --config defconfig
	beep
}

function install() {
	echo "# Installing the kernel..."
	"$SCRIPT_DIR"/kernel-install.sh --srcdir="$KERNEL_SRCDIR" --target=odroidxu4 --remote="$HOST"

	# FIXME: reboot also the machine!!
	ssh "$HOST" reboot || true
	sleep 10s

	rm -f /tmp/odroidversion
	until ssh "$HOST" -o ConnectTimeout=1 uname -r >/tmp/odroidversion; do
		echo "# SSH failed: retrying in a couple of seconds..."
		sleep 2
	done

	beep
	echo "# SSH succeded, version code: $(cat /tmp/odroidversion)"
	local confirm
	read -rp "# Is this ok? [yes/NO] " confirm
	case "$confirm" in
	y | yes | Y | YES)
		return 0
		;;
	esac

	return 1
}

function cherry-pick-continue() {
	git add Makefile
	git commit --no-edit
	git cherry-pick --continue
}

function reset-commit() {
	echo "# Resetting to the correct commit version for bisect..."
	git reset --hard "$(cat "$LAST_BISECT_COMMIT_FILE")"
}

function get_maxn() {
	find "$OUTDIR" | sed 's!.*/!!' | sort -nr | head -1 | cut -d- -f1
}

function run() {
	echo "# Running experiment..."
	ssh "$HOST" /root/APEDF/bisect-single-test.sh
	mkdir -p "$OUTDIR"

	MAXN="$(get_maxn 2>/dev/null || true)"
	if [ -z "$MAXN" ]; then
		MAXN=0
	fi

	MAXN=$((MAXN+1))

	CUR_OUTDIR="$OUTDIR/$MAXN-$(cat "$LAST_BISECT_COMMIT_FILE")"
	scp -r "$HOST:APEDF/bisect-out" "$CUR_OUTDIR"

	ssh "$HOST" reboot >/dev/null 2>/dev/null || true

	echo "# Run successful!!"
	echo "# Check the output of the experiment in $CUR_OUTDIR"
	echo ""
}

function ask-for-outcome {
	local outcome
	read -rp "# Was the experiment output good? [yes,no,skip,abort] " outcome
	case "$outcome" in
	yes)
		echo "Signaling a good version!"
		# NOTE: since our bisect works the opposite way (we are
		# looking for the first good commit, instead of the first
		# bad commit), we have to flip the outcomes for good and
		# bad (but not for skip or abort)
		EXIT_CODE=1
		;;
	no)
		echo "Signaling a bad version!"
		EXIT_CODE=0
		;;
	skip)
		echo "Skipping!"
		EXIT_CODE=125
		;;
	abort | *)
		echo "Aborting!"
		EXIT_CODE=128
		;;
	esac
}

EXIT_CODE=0

function main() {
	if apply-patches && build && install && run; then
		:
	else
		echo "########### Failure! ###########"
	fi

	reset-commit
	ask-for-outcome

	return $EXIT_CODE
}

(
	set -e
	main "$@"
)
