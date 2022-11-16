#!/bin/bash

# NOTE: this command must run in the root of a git repository containing the
# linux kernel. You can work on a shallow clone of the linux kernel by using
#
# git clone --depth 1 [--branch=BRANCH_OR_TAG_NAME] REMOTE_URL LOCAL_FOLDER
#
# And then run this script in LOCAL_FOLDER

SCRIPT_DIR="$(realpath "$(dirname "${BASH_SOURCE[0]}")")"
PATCHES_DIR="$SCRIPT_DIR/patches"
GIT_AM_CMD=(git am -3k --reject)

function export_devel() {
    local tmpdir="$(mktemp -d)"
    git format-patch -k 'apedf-abeni' -o "$tmpdir"
    rm -f "$PATCHES_DIR/02-devel/"*
    cp -a "$tmpdir"/* "$PATCHES_DIR/02-devel/"
    rm -rf "$tmpdir"
}

function main() {
    # Avoid applying if already applied
    if ! [ $(git tag -l "apedf-abeni") ]; then
        echo "Unable to export APEDF development commits!" >&2
        return 1
    fi

    export_devel
    printf "\n    APEDF development commits exported with success!!\n"
    return 0
}

(
    set -e
    main "$@"
)
