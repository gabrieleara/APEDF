#!/bin/bash

(
    set -e

    cpu="$1"
    onoff="$2"

    case "$cpu" in
        big|BIG)
            cpu='4 5 6 7'
            ;;
        little|LITTLE)
            cpu='0 1 2 3'
            ;;
        *)
            echo "Must supply either big or LITTLE as first argument!"
            false
            ;;
    esac

    case "$onoff" in
        on|ON)
            onoff=1
            ;;
        off|OFF)
            onoff=0
            ;;
        *)
            echo "Must supply either on or off as first argument!"
            false
            ;;
    esac

    for c in $cpu ; do
        echo "$onoff" >"/sys/devices/system/cpu/cpu$c/online" || true
    done

    echo "CPUs online:" "$(cat /sys/devices/system/cpu/online)"
)
