#!/bin/bash

SCRIPT_PATH="$(realpath "$(dirname "${BASH_SOURCE[0]}")")"
PROJ_PATH="$(realpath "$SCRIPT_PATH"/..)"

function hostname_waddress() {
    echo "$(hostname) ($(hostname -I | cut -d' ' -f1))"
}

# Prints the complete list of JSON files, each containing a taskset.
function get_all_tsets() {
    local path="$1"
    local pathlen="${#path}"
    local f1=$((pathlen + 5))
    local f2=$((pathlen + 13))
    local f3=$((pathlen + 9))

    find "$path" -name 'ts_n*_i*_u*.json' |
        sort -k 1."$f1"n -k 1."$f2"nr -k 1."$f3"n
}

# # Prints the list of all utilizations as declared in the
# # directory given as first argument
# function get_all_utils() {
#     (
#         for arg in "$@"; do
#             echo "$arg"
#         done
#     ) |
#         sed 's/\.json//g' |
#         sed 's/\.txt//' |
#         cut -d'_' -f3 |
#         sort -nr |
#         uniq
#     # NOTE: sorting first by utilization (descending) and
#     # then by index (ascending)
# }

(
    set -e

    SCRIPT_PATH=$(get_script_path)
    source "$SCRIPT_PATH/util/cpufreq.sh"
    source "$SCRIPT_PATH/util/telegram-tokens.sh" 2>/dev/null || true
    source "$SCRIPT_PATH/util/telegram.sh"

    # Arguments of this script:
    #  1. The directory where to find all tasksets to run
    #  2. The directory where to put all the results
    #  3. The path to the power sampler application root
    #     directory [optional, default=apps/power-sampler]
    #  4. The log level for rt-app [optional, default=10]

    if ! [ "$(id -u)" = 0 ]; then
        echo "This script must be run as root" >&2
        false
    fi

    ruid=$(id -ru)
    rgid=$(id -rg)

    if [ $# -lt 2 ]; then
        echo "You must provide the input and output directories respectively!"
        false
    fi

    DIR_IN="$1"
    DIR_OUT="$2"

    APPS_DIR="./apps/"
    LOG_LEVEL=10

    if [ $# -gt 2 ]; then
        APPS_DIR="$3"
    fi

    if [ $# -gt 3 ]; then
        LOG_LEVEL="$4"
    fi

    SAMPLER_DIR="$APPS_DIR/power-sampler"
    RTAPP_DIR="$APPS_DIR/rt-app"
    SAMPLER_APP="$SAMPLER_DIR/build/sampler"
    RTAPP="$RTAPP_DIR/src/rt-app"
    "$SCRIPT_PATH/util/buildapps.sh" "$APPS_DIR" cleanall sampler rtapp

    power_file="$(mktemp)"

    # # Uncomment this line to disable the 95/100 limit for
    # # RT applications
    # sysctl -w kernel.sched_rt_runtime_us=-1 >/dev/null

    # On kernel 5 for the Odroid, maximizing all fans is not
    # a good idea in software, so make sure to maximize them
    # "in hardware" (connect the fan to VCC)!

    tsets=($(get_all_tsets "$DIR_IN"))
    ntsets="${#tsets[@]}"

    # path="$DIR_IN"
    # pathlen="${#path}"
    # f1=$((pathlen + 7))
    # f2=$((pathlen + 4))
    # echo "Tsets:"
    # (
    #     for t in "${tsets[@]}" ; do
    #         echo "$t"
    #     done
    # ) | sort -k 1."$f1"nr -k 1."$f2"n --debug

    i=0
    j=10

    echo "Experiments are starting!"

    # Making the rt-app log directory
    mkdir -p /tmp/rt-app-logs
    mkdir -p "$DIR_OUT"

    # Set maximum frequency to a low (but not too low) value
    # to avoid thermal throttling
    "$SCRIPT_PATH/cpuonoff.sh"  big     on
    "$SCRIPT_PATH/cpuonoff.sh"  little  on

    cpufreq_governor_setall performance

    cpufreq_policy_frequency_set_max 0 1400000
    cpufreq_policy_frequency_set_max 4 1400000

    # Turn one of the islands off
    "$SCRIPT_PATH/cpuonoff.sh"  big     on
    "$SCRIPT_PATH/cpuonoff.sh"  little  off

    # Disable deadline admission control (DANGEROUS!)
#    sysctl -w kernel.sched_rt_runtime_us=-1 >/dev/null

    for ts in "${tsets[@]}" ; do
        i=$((i+1))
        printf 'Running test [%02d/%02d] defined in %s ...' "$i" "$ntsets" "$ts"

#        nice -n -20 "$SAMPLER_APP" >"$power_file" 2>/dev/null &
#        power_pid="$!"
        sleep 2s

        nice -n -20 "$RTAPP" -l "$LOG_LEVEL" "$ts"
        sleep 1s

#        kill "$power_pid"
        sync
        wait

        ts_base="$(basename "$ts")"
        ts_base="${ts_base%.*}"
        power_file_out="${ts_base}.power"
        rtapp_dir_out="${ts_base}.rt-app.d"

        # cp      "$power_file"       "${DIR_OUT}/${power_file_out}"
        cp -r   "/tmp/rt-app-logs"  "${DIR_OUT}/${rtapp_dir_out}"

        # chown -R "${ruid}:${rgid}"  "${DIR_OUT}/${power_file_out}"
        chown -R "${ruid}:${rgid}"  "${DIR_OUT}/${rtapp_dir_out}"

        echo "DONE! Cooling down a bit..."
        # Memory caches tend to fill up rather quickly, let's avoid that
        sync
        echo 1 > /proc/sys/vm/drop_caches

        # 2 minutes of cooldown
        sleep 120s

        if [ $i = $j ]; then
            telegram_notify \
                "Completion rate on $(hostname_waddress): $i / $ntsets" || true
            j=$((j+10))
        fi
    done

    telegram_notify "Experiment on $(hostname_waddress) was a success!"

    rm "${power_file}"
)

SCRIPT_PATH=$(get_script_path)
source "$SCRIPT_PATH/util/telegram-tokens.sh" 2>/dev/null || true
source "$SCRIPT_PATH/util/telegram.sh"
telegram_notify "Experiment on $(hostname_waddress) terminated!"
