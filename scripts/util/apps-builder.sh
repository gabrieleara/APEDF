#!/bin/bash

SCRIPT_NAME=$(basename "${BASH_SOURCE[0]}")

APPS_LIST=(rtapp) # sampler

function clean_sampler() {
    echo " + clean sampler..."

    rm -rf "$SAMPLER_DIR/build"
}

function clean_rtapp() {
    echo " + clean rtapp..."

    rm -rf "$RTAPP_DIR"/autom4te.cache
    rm -rf "$RTAPP_DIR"/build-aux
}

function build_sampler() {
    echo " + build sampler"

    # runuser -u "$ruid" --
    cmake -S "$SAMPLER_DIR" -B "$SAMPLER_DIR/build"
    # runuser -u "$ruid" --
    cmake --build "$SAMPLER_DIR/build" -j "$(nproc)"
}

function build_rtapp() {
    echo " + build rtapp"

    pushd "$RTAPP_DIR" >/dev/null
    # runuser -u "$ruid" --
    ./autogen.sh
    # runuser -u "$ruid" --
    ./configure --with-deadline
    # runuser -u "$ruid" --
    make -j "$(nproc)"
    popd >/dev/null
}

function usage() {
    echo "
Usage: $SCRIPT_NAME APPS_DIR_PATH [--clean] [all] APP_NAMES

    At least one APP_NAME to build (or the value 'all') must be supplied!
    Supported apps: ${APPS_LIST[*]}
"
}

function parse_args() {
    local arg
    local args

    args=()
    CLEAN=n

    for arg in "$@"; do
        case "$arg" in
        --clean)
            CLEAN=y
            ;;
        *)
            args+=("$arg")
            ;;
        esac
    done

    if [ "${#args[@]}" -lt 2 ]; then
        usage
        return 1
    fi

    APPS_DIR_PATH="${args[0]}"
    APPS=("${args[@]:1}")

    RTAPP_DIR="$APPS_DIR_PATH/rt-app"
    SAMPLER_DIR="$APPS_DIR_PATH/sampler"
}

function contains() {
    if [[ $1 =~ (^|[[:space:]])$2($|[[:space:]]) ]]; then
        return 0
    fi
    return 1
}

function check_apps() {
    local app
    for app in "${APPS[@]}"; do
        if [ "$app" != all ] && ! contains "${APPS_LIST[*]}" "$app"; then
            echo "$SCRIPT_NAME: Error - Unsupported argument '$app'" >&2
            usage
            return 1
        fi
    done
}

function run() {
    if [ $2 != all ]; then
        APPS_LIST=("$2")
    fi

    local app
    for app in "${APPS_LIST[@]}"; do
        "$1_$app"
    done
}

function main() {
    parse_args "$@"
    check_apps

    local app
    if [ "$CLEAN" = y ]; then
        for app in "${APPS[@]}"; do
            run clean "$app"
        done
    fi

    for app in "${APPS[@]}"; do
        run build "$app"
    done

    echo " + done!"
}

(
    set -e
    main "$@"
)
