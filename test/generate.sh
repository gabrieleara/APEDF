#!/bin/bash

# ======================================================== #
# ---------------------- FUNCTIONS ----------------------- #
# ======================================================== #

function calc() {
    echo "scale=4; $* " | bc -l
}

function trim() {
    xargs
}

function get_total_utilization() {
    # It is the theoretical maximum utilization possible on
    # the system, calculated by summing the capacities of
    # each <ONLINE> CPU.

    # NOTE: the maximum capacity of the fastest CPU is
    # always represented as 1024
    local CAP_MAX=1024

    local cap=0
    local total_cap=0

    for i in /sys/devices/system/cpu/cpu*; do
        # FIXME: matches some files/dirs that are not a cpu directory!

        # Printing to variable path
        if [ "$(cat "$i/online")" != 1 ]; then
            continue
        fi

        cap="$(cat "$i/cpu_capacity")"
        total_cap=$((total_cap + cap))
    done

    calc "$total_cap / $CAP_MAX"
}

# Generates a specific number of random numbers. Arguments:
#  1. RNG seed. Use -1 or an empty string for no seed.
#  2. Number of numbers to generate. Use no argument to
#     generate only one.
function rng() {
    local seed=""
    local nrands=1

    if [ "$#" -gt 0 ]; then
        seed="$1"
        if [ "$seed" -lt 0 ]; then
            seed=""
        fi
    fi

    if [ "$#" -gt 1 ]; then
        nrands="$2"
    fi

    awk "BEGIN {
        srand($seed)
        for (i = 0; i < $nrands ; i++ ) {
            print int(1 + rand() * 10000)
        }
    }"
}

# Generates a list of seeds to feed taskgen using the GT_SEED
# and GT_NUM_TASKSETS
function gen_seeds_list() {
    rng "$GT_SEED" "$GT_NUM_TASKSETS"
}

# Generates the list of utilizations for the tasksets.
function gen_utils_list() {
    local util_total
    local util_min
    local util_max
    local util_inc
    local util
    local check=0

    util_total="$(get_total_utilization)"
    util_min="$(calc "$util_total * $GT_UMIN_FRAC")"
    util_max="$(calc "$util_total * $GT_UMAX_FRAC")"
    util_inc="$(calc "($util_max - $util_min) / $GT_UTILS_NUM")"

    util="$util_min"
    for ((i = 0; i < "$GT_UTILS_NUM"; i++)); do
        util=$(calc "$util + $util_inc")

        if [ "$(calc "$util > $util_max")" = 1 ]; then
            util="$util_max"

            if [ "$check" = 1 ]; then
                echo 'ERROR: could not generate enough tasksets!' >&2
                false
            fi
            check=1
        fi

        echo "$util"
    done
}

function get_seeds_list() {
    if [ "${#GT_SEEDS_LIST[@]}" -gt 0 ]; then
        echo 'WARNING: using a forced list of seeds!' >&2

        if [ "${#GT_SEEDS_LIST[@]}" -lt "$GT_NUM_TASKSETS" ]; then
            echo 'ERROR: wrong length of the seeds list!' >&2
            false
        fi

        for s in "${GT_SEEDS_LIST[@]}"; do
            echo "$s"
        done

        return
    fi

    gen_seeds_list
}

function get_utils_list() {
    if [ "${#GT_UTILS_LIST[@]}" -gt 0 ]; then
        echo 'WARNING: using a forced list of utilizations!' >&2
        echo 'WARNING: YOU are responsible to check that the system is feasible!' >&2

        for u in "${GT_UTILS_LIST[@]}"; do
            echo "$u"
        done

        return
    fi

    gen_utils_list
}

# Generates a single taskset. Arguments:
#  1. The seed to use for taskgen.
#  2. The number of tasks in the taskset.
#  3. The total utilization.
function generate_taskset() {
    local seed="$1"
    local ntasks="$2"
    local util="$3"

    # Quick argument reference for taskgen:
    # - -S seed for the random number generator
    # - -d distribution of the periods (=logunif ->
    #   logarithmic uniform distribution)
    # - -s number of tasksets to generate (=1)
    # - -n number of tasks per taskset
    # - -u total taskset utilization
    # - -p minimum period
    # - -q maximum period
    # - -g period granularity
    # - --round-C rounds execution times to the nearest
    #   integer
    # - -f output format as a python template string.

    "$TASKGEN3" \
        -S "$seed" \
        -d logunif \
        -s 1 \
        -n "$ntasks" \
        -u "$util" \
        -p 100000 \
        -q 1200000 \
        -g 10000 \
        --round-C \
        -f "%(C)d %(T)d"

}

function check_runtimes() {
    printf '%s' $(sed '/^[[:space:]]*$/d' <"$1" | awk ' { if ($1 < 4000) print nope } ' | wc -l)
}

function fix_runtimes() {
    local infile=$1
    local min_value
    local multiplier

    min_value=$(sort -nk 1 "$infile" | head -n 1 | cut -d' ' -f1)
    # echo "MIN_VALUE = $min_value" >&2
    multiplier=$(bc <<EOF
define ceil_divide(dividend, divisor) {
    return (dividend + divisor - 1) / divisor
}
ceil_divide(5000, $min_value)
EOF
)
    # echo "MULTIPLIER = $multiplier" >&2
    awk -v multiplier=$multiplier  '{ print $1*multiplier, $2*multiplier }' <"$1"
}

# Checks that the total utilization provided by taskgen is
# not above the maximum
function check_utilization() {
    local sum_util=0

    sum_util=$(
        (
            sed '/^[[:space:]]*$/d' |
                awk '
            {
                sum_util += ($1 / $2)
            } END {
                print sum_util
            }
        '
        ) <"$1"
    )

    # printf -v sum_util "%.4f" "${sum_util}"

    echo -e "CHECK:\texpected\t$2\tgot\t${sum_util}"
}

(
    set -e

    # ==================================================== #
    # ---------------- SCRIPT PARAMETERS ----------------- #
    # ==================================================== #

    # Script parameters are the following ones. You can
    # override them by supplying as first parameter a script
    # that will be sourced. BE CAREFUL!

    # The root directory where to create the tasksets
    GT_OUT_DIR="./tasksets"

    # Number of tasks per taskset
    GT_NUM_TASKS_LIST=(8 12 16) # 6

    # Number of tasksets
    GT_NUM_TASKSETS=10

    # Number of different utilizations to test within the
    # given range
    GT_UTILS_NUM=28

    # The fraction of the total utilization to use as
    # starting point for the experiment
    GT_UMIN_FRAC=0.25

    # The fraction of the total utilization to use as ending
    # point for the experiment
    GT_UMAX_FRAC=0.95

    # List of utilizations to use. Overrides the generation
    # of the list staring from the capacity of online CPUs.
    GT_UTILS_LIST=(1.0 1.15 1.3 1.45 1.6 1.75 1.9 2.05 2.2 2.35 2.5 2.6 2.7 2.8 2.9 3.0 3.1 3.2 3.3 3.4 3.5 3.6)

    # GT_UTILS_LIST=()

    # The seed for the random number generator (used to
    # generate the seeds to feed taskgen! what a trip, uh?)
    GT_SEED=13994

    # Use this to force a set of taskgen seeds to use
    # instead of the generated ones. The list of seeds used
    # is printed to stdout upon generation. Technically,
    # such a list should not be necessary, but awk
    # documentation states that different awk
    # implementations may use different rand
    # implementations, so please use the list if you may
    # expect the output of this script to change even when
    # mantaining the same GT_SEED value.
    GT_SEEDS_LIST=()

    # The maximum fraction of the reserved runtime the task can actually run
    # for. Must be between 0 and 1.
    GT_RT_FRACTION=.95

    # The minimum amount of runtime (in us) to remove from the task duration
    # starting from the reserved runtime. Must be non negative.
    #
    # In practice, applying the GT_RT_FRACTION and the GT_RT_REMOVE gives us two
    # different runtimes. The smallest of the two is used to specify the amount
    # the task will run for, so that both rules are satisfied at the same time
    # without removing too runtime.
    GT_RT_REMOVE=0

    # The minimum test duration in seconds.
    GT_RT_MIN_DURATION=20

    # The maximum test duration in seconds.
    GT_RT_MAX_DURATION=600

    # The calibration for RT-App.
    # USE:
    # - LITTLE  core @ 1.4 GHz => 204
    # - big     core @ 1.4 GHz => 92
    GT_RT_CALIBRATION=92

    # ==================================================== #
    # ----------------------- MAIN ----------------------- #
    # ==================================================== #

    SCRIPT_PATH="$(realpath "${BASH_SOURCE[0]}")"
    SCRIPT_NAME="$(basename "${BASH_SOURCE[0]}")"
    SCRIPT_DIR="$(realpath "$(dirname "$SCRIPT_PATH")")"

    TASKGEN3="$(realpath "$SCRIPT_DIR"/scripts/generation/taskgen3.py)"
    TASKSET2JSON="$(realpath "$SCRIPT_DIR"/scripts/generation/taskset2json.py)"

    if [ $# -gt 0 ]; then
        echo "WARNING: using the first parameter as a fixed configuration script!" >&2
        echo "WARNING: READING FROM $1" >&2

        . "$1"
    fi

    GT_SEEDS_LIST=($(get_seeds_list | xargs))
    GT_UTILS_LIST=($(get_utils_list | xargs))

    GT_UTILS_NUM="${#GT_UTILS_LIST[@]}"
    GT_NUM_TASKS_NUM="${#GT_NUM_TASKS_LIST[@]}"

    max_quota="${GT_UTILS_LIST[-1]}"

    echo ""
    echo "Generating tasksets with the following utils:"
    echo "${GT_UTILS_LIST[*]}"
    echo ""

    echo "Generating tasksets with the following seeds:"
    echo "${GT_SEEDS_LIST[*]}"
    echo ""

    mkdir -p "$GT_OUT_DIR"
    tset_name=
    tset_file=
    text_file=
    json_file=

    tested_seeds=()

    # for each number of tasks
    for ((k = 0; k < $GT_NUM_TASKS_NUM; k++)); do
        num_tasks="${GT_NUM_TASKS_LIST[$k]}"

        printf -v num_tasks_dd "%02d" "$num_tasks"
        curdir="$GT_OUT_DIR/$num_tasks_dd"
        mkdir -p "$curdir"

        # for each utilization
        for ((j = 0; j < "$GT_UTILS_NUM"; j++)); do
            util="${GT_UTILS_LIST[$j]}"

            if (($(echo "0 >= $util" | bc -l))); then
                continue
            fi

            tested_seeds=()

            # for each repetition
            for ((i = 0; i < "$GT_NUM_TASKSETS"; i++)); do
                seed="${GT_SEEDS_LIST[$i]}"

                doitagain=1

                while [ "$doitagain" = 1 ]; do
                    printf 'Generating taskset with %02d tasks, util %.4f, index %02d, (seed %d)' \
                        "$num_tasks" "$util" "$i" "$seed"

                    tested_seeds+=("${seed}")

                    # Printing to variable tset_file
                    printf -v tset_name \
                        'ts_n%s_i%02d_u%.4f' "$num_tasks_dd" "$i" "$util"

                    tset_file="${curdir}/${tset_name}"
                    text_file="${tset_file}.txt"
                    json_file="${tset_file}.json"

                    generate_taskset "$seed" "$num_tasks" "$util" \
                        >"$text_file" # 2>/dev/null

                    printf " Runtimes check:"
                    num_tasks_below_threshold=$(check_runtimes "$text_file")
                    if [ $num_tasks_below_threshold -gt 0 ]; then
                        printf " had to fix!"
                        seed=$((seed+1))
                        while [[ " ${GT_SEEDS_LIST[*]} ${tested_seeds[*]} " =~ " ${seed} " ]]; do
                            seed=$((seed+1))
                        done
                    else
                        printf " OK!"
                        doitagain=0
                    fi

                    printf '\n'
                done

                # # NOTE: this could be necessary if the tasks exceed the maximum
                # check_utilization "$text_file" "$util"

                "$TASKSET2JSON" \
                    -r "$GT_RT_FRACTION" \
                    -R "$GT_RT_REMOVE" \
                    -m "$GT_RT_MIN_DURATION" \
                    -M "$GT_RT_MAX_DURATION" \
                    -c "$GT_RT_CALIBRATION" \
                    -q "$max_quota" \
                    <"$text_file" >"$json_file"
                # Option -l is not used anymore
                # -l "$tset_name" \

            done
        done
    done

    params_file="$GT_OUT_DIR/params.sh"

    echo ''
    echo 'DONE!'
    echo ''
    echo 'Generating a script to generate all parameters to reproduce these tasksets in the output directory.'
    echo 'To use it, source it before running this script again:'
    echo ''
    echo '$ .' "$params_file"
    echo ''

    touch "$params_file"
    chmod +x "$params_file"
    cat <<EOF >"$params_file"
#!/bin/bash
# Auto-generated file, do not edit

export GT_OUT_DIR="${GT_OUT_DIR}"
export GT_NUM_TASKS_LIST=(${GT_NUM_TASKS_LIST[@]})
export GT_NUM_TASKSETS="${GT_NUM_TASKSETS}"
export GT_UTILS_NUM="${GT_UTILS_NUM}"
export GT_UMIN_FRAC="${GT_UMIN_FRAC}"
export GT_UMAX_FRAC="${GT_UMAX_FRAC}"
export GT_UTILS_LIST=(${GT_UTILS_LIST[@]})
export GT_SEED="${GT_SEED}"
export GT_SEEDS_LIST=(${GT_SEEDS_LIST[@]})
export GT_RT_FRACTION="${GT_RT_FRACTION}"
export GT_RT_REMOVE="${GT_RT_REMOVE}"
export GT_RT_MIN_DURATION="${GT_RT_MIN_DURATION}"
export GT_RT_MAX_DURATION="${GT_RT_MAX_DURATION}"
export GT_RT_CALIBRATION="${GT_RT_CALIBRATION}"
EOF
)
