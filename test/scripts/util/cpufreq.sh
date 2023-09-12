#!/bin/bash

# +--------------------------------------------------------+
# |                   Utility Functions                    |
# +--------------------------------------------------------+

# Generic function that returns the value of an attribute of a policy
function cpufreq_policy_get_attr() {
    cat "/sys/devices/system/cpu/cpufreq/policy$1/$2"
}

# Generic function that sets the value of an attribute of a policy
function cpufreq_policy_set_attr() {
    echo "$3" >"/sys/devices/system/cpu/cpufreq/policy$1/$2"
}

# Blocking function that ensures the correct value has been set for the given
# attribute, repeating the write if necessary
function cpufreq_policy_set_attr_check() {
    local policy="$1"
    local attr="$2"
    local value="$3"
    local interval="$4"
    local maxcount="$5"

    # Optional arguments
    [[ $# -lt 4 ]] && interval="0.5s"
    [[ $# -lt 5 ]] && maxcount="20"

    local curr_value
    local counter=0

    curr_value=$(cpufreq_policy_get_attr "$policy" "$attr")
    while [ "$curr_value" -ne "$value" ]; do
        # Could not set the desired value
        if [ "$counter" -gt "$maxcount" ]; then
            echo "ERROR: Unable to set on policy $policy attribute $attr to value $value! Current value: $curr_value" >&2
            return 1
        fi

        # Write and check after an interval
        cpufreq_policy_set_attr "$policy" "$attr" "$value"

        sleep "$interval"

        curr_value=$(cpufreq_policy_get_attr "$policy" "$attr")
        counter=$((counter + 1))
    done

    return 0
}

# +--------------------------------------------------------+
# |                        Getters                         |
# +--------------------------------------------------------+

# List all available CPU frequency policies in the system
function cpufreq_policy_list() {
    local PREFIX="/sys/devices/system/cpu/cpufreq/policy"
    for p in "${PREFIX}"*; do
        echo "$p" | sed "s#${PREFIX}##g"
    done
}

# Get all the frequencies available for the given policy (ARM ONLY)
function cpufreq_policy_frequency_list() {
    cpufreq_policy_get_attr "$1" "scaling_available_frequencies" |
        cut -d' ' --output-delimiter=$'\n' -f1-
}

# Get all the cpus associated to the given policy
function cpufreq_policy_cpu_list() {
    cpufreq_policy_get_attr "$1" "affected_cpus" |
        cut -d' ' --output-delimiter=$'\n' -f1-
}

# List all CPU numbers in the system
function cpufreq_cpu_list() {
    # FIXME: is this regex broken somehow? It works, but is it as originally intended?
    for c in $(ls /sys/devices/system/cpu/ | grep cpu\[0-9*\] | sed -r "s/cpu//g"); do
        echo "$c"
    done
}

# Get maximum frequency available for the given policy
function cpufreq_policy_frequency_max() {
    cpufreq_policy_get_attr "$1" "cpuinfo_max_freq"
}

# Get minimum frequency available for the given policy
function cpufreq_policy_frequency_min() {
    cpufreq_policy_get_attr "$1" "cpuinfo_min_freq"
}

# Get the governor for the given policy
function cpufreq_policy_governor_get() {
    cpufreq_policy_get_attr "$1" "scaling_governor"
}

# Find a policy different than the current one, if any,
# otherwise prints the given policy.
#
# Arguments:
#  1. Policy we want to "skip"
function cpufreq_policy_find_another() {
    local policy
    local policy_other

    policy="$1"
    for policy_other in $(cpufreq_policy_list | sort -n); do
        if [ "$policy_other" != "$policy" ]; then
            echo "$policy_other"
            return
        fi
    done
    echo "$policy"
}


# +--------------------------------------------------------+
# |                        Setters                         |
# +--------------------------------------------------------+


# Blocking call that sets the maximum frequency for the given CPU/policy.
function cpufreq_policy_frequency_set_max() {
    local policy="$1"
    local frequency="$2"

    cpufreq_policy_set_attr_check "$policy" "scaling_max_freq" "$frequency"
}

# Blocking call that sets the desired frequency for the given CPU/policy,
# if not selected already. Governor can be 'performance' or 'userspace'.
function cpufreq_policy_frequency_set() {
    local policy=$1
    local frequency=$2

    local max_frequency
    local governor

    max_frequency=$(cpufreq_policy_frequency_max "$policy")
    governor=$(cpufreq_policy_governor_get "$policy")

    case "$governor" in
    performance)
        cpufreq_policy_set_attr_check "$policy" "scaling_max_freq" "$max_frequency"
        cpufreq_policy_set_attr_check "$policy" "scaling_min_freq" "$frequency"
        cpufreq_policy_set_attr_check "$policy" "scaling_max_freq" "$frequency"
        ;;
    userspace)
        # cpufreq_policy_set_attr_check "$policy" "scaling_setspeed" "$max_frequency"
        cpufreq_policy_set_attr_check "$policy" "scaling_setspeed" "$frequency"
        ;;
    *)
        echo "Unsupported governor:" "$governor" 1>&2
        false
        ;;
    esac
}

# Set maximum frequency to all policies (actual value depends on each policy)
function cpufreq_policy_frequency_maxall() {
    for p in $(cpufreq_policy_list); do
        cpufreq_policy_frequency_set "$p" "$(cpufreq_policy_frequency_max "$p")"
    done
}

# Set minimum frequency to all policies  (actual value depends on each policy)
function cpufreq_policy_frequency_minall() {
    for p in $(cpufreq_policy_list); do
        cpufreq_policy_frequency_set "$p" "$(cpufreq_policy_frequency_min "$p")"
    done
}

# Set the specified governor for the given policy
# (assumes the governor is valid and can be accepted by the policy)
function cpufreq_policy_governor_set() {
    cpufreq_policy_set_attr "$1" "scaling_governor" "$2"
}

# Set the specified governor for all policies
# (assumes the governor is valid and can be accepted by each policy)
function cpufreq_governor_setall() {
    for p in $(cpufreq_policy_list); do
        cpufreq_policy_governor_set "$p" "$1"
    done
}
