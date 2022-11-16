#!/bin/bash

function dir_sampler_check() {
    if ! [ -d "$SAMPLER_DIR" ]; then
        echo "Could not find the sampler original directory!" >&2
        echo "Please specify the right apps directory!" >&2
        false
    fi
}

function dir_rtapp_check() {
    if ! [ -d "$RTAPP_DIR" ]; then
        echo "Could not find the rt-app original directory!" >&2
        echo "Please specify the right apps directory!" >&2
        false
    fi
}

function clean_sampler() {
    echo "Cleaning the sampler application..."
    dir_sampler_check
    rm -rf "$SAMPLER_DIR/build"
}

function clean_rtapp() {
    echo "Cleaning the rt-app application..."
    dir_rtapp_check
    rm -rf "$RTAPP_DIR"/autom4te.cache
    rm -rf "$RTAPP_DIR"/build-aux
}

function build_sampler() {
    echo "Configuring and building the sampler application..."
    if ! [ -d "$SAMPLER_DIR" ]; then
        echo "Could not find the sampler original directory!" >&2
        echo "Please specify the right apps directory!" >&2
        false
    fi
    # runuser -u "$ruid" --
    cmake -S "$SAMPLER_DIR" -B "$SAMPLER_DIR/build"
    # runuser -u "$ruid" --
    cmake --build "$SAMPLER_DIR/build" -j "$(nproc)"
}


function build_rtapp() {
    echo "Configuring and building the rt-app application..."
    dir_rtapp_check

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
    echo "USAGE: $0 apps-dir-path [cleanall] [rtapp] [sampler]"
    echo "NOTE: at least one app to build or the 'cleanall' option must be supplied!"
}

(
    set -e

    if [ $# -lt 2 ] ; then
        usage
        false
    fi

    APPS_DIR="$1"
    shift

    SAMPLER_DIR="$APPS_DIR/power-sampler"
    RTAPP_DIR="$APPS_DIR/rt-app"

    for arg in $@ ; do
        case "$arg" in
            cleanall)
                clean_sampler
                clean_rtapp
                ;;
            sampler)
                build_sampler
                ;;
            rtapp)
                build_rtapp
                ;;
            *)
                echo "Unrecognized argument: $arg"
                usage
                false
        esac
    done
)
