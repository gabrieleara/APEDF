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

function apply_energy_exynos() {
    # This should be applied only once
    "${GIT_AM_CMD[@]}" "$PATCHES_DIR"/00-energy-exynos/*.patch
    git tag -a 'energy-exynos' -m "Exynos5422 CPU Energy Model"
}

function apply_apedf_abeni() {
    # This should be applied only once
    "${GIT_AM_CMD[@]}" "$PATCHES_DIR"/01-apedf/*
    git tag -a 'apedf-abeni' -m 'Implementation of AP-EDF by Luca Abeni'
}

function apply_devel() {
    # This can be applied multiple times on top of apedf-abeni
    git checkout 'apedf-devel'
    git reset --hard 'apedf-abeni'
    "${GIT_AM_CMD[@]}" "$PATCHES_DIR"/02-devel/*
    git tag -af 'development' -m 'Current point in development'
}

function apply_walter() {
    # This is incomplete, but it should behave like apply-devel (if possible)
    git checkout 'apedf-abeni'
    git checkout -b walter
    # TODO:
}

function main() {
    cat <<EOF
    Startying to apply APEDF patches, in case of failure check for .rej files in
    your Linux repository.

    Try to fix rejected hunks by following these steps:
    - edit the original patch file of the failed patch
    - delete the rej files
    - run 'git am --abort' to reset the state of your repository
    - re-run this command in the same way as you did before

    Keep fixing patches until it all works.
    This should not be necessary, but you never know.

    Anyway, starting the process now.

EOF

    if ! git rev-parse --verify apedf-devel >/dev/null; then
        git checkout -B apedf-devel
        git tag -a 'apedf-begin' -m 'Beginning of APEDF development'
    else
        git checkout -B apedf-devel
    fi

    # FIXME: add an option to check whether this patch should be applied or not
    # # Avoid applying if already applied
    # if ! [ $(git tag -l "energy-exynos") ]; then
    #     apply_energy_exynos
    # fi

    # Avoid applying if already applied
    if ! [ $(git tag -l "apedf-abeni") ]; then
        apply_apedf_abeni
    fi

    # apply_walter
    apply_devel

    printf "\n    APEDF applied with success!!\n"

    return 0
}

(
    set -e
    main "$@"
)
