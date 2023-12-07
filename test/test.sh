#!/bin/bash

# TODO:
# - implement a maximum timeout for the cooldown

# --------------------------- TEST PARAMETERS --------------------------- #

# Used to discard and repeat an experiment
THERM_DISCARD=70

# Used to delay the beginning of the next experiment
THERM_CONTINUE=45

# How often in seconds the temperature must be checked during experiments
THERM_MONITOR_INTERVAL=.5

# Cgroups that should be created by the script during experiment setup
CGROUPS=(
	# Default cgroup cpuset will shrink automatically when setting the
	# other cpus to the 'big' group.
	"big 4-7 root"
)

# Cgroup in which rt-app shall execute
CGROUP_TASKSETS=big

# Must be a CPU associated with any cpu inside the selected cgroup
CPUFREQ_CPU=4

# Maximum frequency that can be used on the island associated to the
# selected cgroup
CPUFREQ_MAXFREQ="1400000" # in khz

# Where the output is saved (relative to test directory location)
OUTDIR=./out

# For how long rt-app will execute
RTAPP_TIMEOUT=60

# Log-level for rt-app (10 = none)
RTAPP_LOGLEVEL=10

# What to set as rt-limit for the system (-1 disable rt throttling)
RTLIMIT=

# ---------------------------- NOTIFICATIONS ---------------------------- #

NOTIFICATION_MULTIPLE=10

function notify() {
	"$NOTIFIER" "$@"
}

function notify_progress() {
	local progress="$1"
	local total="$2"
	if (( progress % NOTIFICATION_MULTIPLE != 0 )); then
		# Skip notification
		return
	fi

	notify progress "[$progress/$total]"
}

# -------------------- TEMPERATURE CHECK AND MONITOR -------------------- #

function therm_files() {
	ls -1 /sys/class/thermal/thermal_zone*/temp
}

# Prints N temperatures in Celsius, one per line
function therm_get() {
	therm_files | xargs cat 2>/dev/null | awk '{ print $0 / 1000.0 }'
}

# Check temperatures in STDIN against the one provided as single argument
function therm_all_le() {
	local temperature="$1"
	if awk '$1 > '"${temperature}"' { print 1 }' | grep '1' >/dev/null; then
		# Match, which means: temperature too high
		return 1
	else
		# No match, which means: temperature ok
		return 0
	fi
}

function therm_can_begin() {
	therm_get | therm_all_le "${THERM_CONTINUE}"
}

function therm_must_discard() {
	tr -s ' ' '\n' <"$1" | therm_all_le "${THERM_DISCARD}"
}

# Override the error code to always be a success on SIGINT
function therm_monitor_signal() {
	THERM_MONITOR_CONTINUE=0
}

THERM_MONITOR_CONTINUE=1
THERM_MONITOR_PID=''

# Process that will continuously monitor the temperature (one sample per
# line, multiple columns), terminate with SIGUSR1 please
function therm_monitor() {
	while [ "$THERM_MONITOR_CONTINUE" = 1 ]; do
		therm_get | xargs echo
		sleep "${THERM_MONITOR_INTERVAL}"
	done

}

function therm_monitor_start() {
	(
		trap therm_monitor_signal SIGHUP SIGINT SIGTERM SIGTSTP
		therm_monitor >"$THERM_MONITOR_OUT"
	) &
	THERM_MONITOR_PID="$!"
	disown -r "$THERM_MONITOR_PID"
}

function therm_monitor_stop() {
	kill -INT "$THERM_MONITOR_PID" >/dev/null 2>/dev/null || true

	# Wait for the process to finish
	if [ -n "$THERM_MONITOR_PID" ]; then
		tail --pid="$THERM_MONITOR_PID" -f /dev/null
	fi

	# For the next iteration
	THERM_MONITOR_CONTINUE=1
}

# ---------------------------- POWER MONITOR ---------------------------- #

# The power monitor uses a python script to read from the serial and a
# couple of piped commands to cut the relevant information.
#
# This implementation is an improvement over previous versions because it
# runs less programs concurrently to rtapp, delegating most other
# operations to post-processing.

TMPDIR=''
POWER_MONITOR_OUT=''
POWER_MONITOR_PID=''

function power_monitor_start() {
	# Remember in post-processing (collecting) phase to check for:
	# - the number of fields in each row
	# - the checksum present in each row
	# - filter out unneded data columns (we keep it all now to avoid
	#   doing conformance checks online)
	"$SERIAL_LOGGER" \
		--port /dev/ttyUSB0 \
		--baudrate 230400 \
		--bytesize 8 \
		--parity N \
		--stopbits 1 \
		--rtscts 0 \
		>"$POWER_MONITOR_OUT" &
	POWER_MONITOR_PID="$!"
	disown -r "$POWER_MONITOR_PID"
}

function power_monitor_stop() {
	if [ -z "$POWER_MONITOR_PID" ]; then
		return 0
	fi

	# Send SIGINT and wait for program termination
	kill -SIGINT "$POWER_MONITOR_PID"
	tail --pid="$POWER_MONITOR_PID" -f /dev/null
	POWER_MONITOR_PID=''
}

# --------------------------- MANAGE CGROUPS ---------------------------- #

function cgroupv2_init() {
	# cgroups created without the cpuset parameter in the root cgroup
	# will NOT be able to enable the cpuset controller later
	/bin/echo "+cpuset" >"/sys/fs/cgroup"/cgroup.subtree_control
}

function cgroupv2_create() {
	cgroupv2_init
	mkdir "/sys/fs/cgroup/$1"
}

function cgroupv2_cpuset() {
	/bin/echo "$2" >"/sys/fs/cgroup/$1/cpuset.cpus"
}

function cgroupv2_partition() {
	/bin/echo "$2" >"/sys/fs/cgroup/$1/cpuset.cpus.partition"
}

function cgroupv2_remove() {
	rmdir "/sys/fs/cgroup/$1"
}

function cgroupv2_exists() {
	test -d "/sys/fs/cgroup/$1"
}

# Arguments:
# - name of cpuset to run into
# - command to run on said cpuset, started in a separate shell
function cgroupv2_run() {
	(
		# NOTICE: BASHPID, NOT $$ !!
		/bin/echo $BASHPID >"/sys/fs/cgroup/$1/cgroup.procs"
		"${@:2}"
	)
}

function cgroupv2_create_all() {
	local cg
	local cg_array
	local cg_name
	local cg_cpus
	local cg_partition
	for cg in "${CGROUPS[@]}"; do
		IFS=' ' read -r -a cg_array <<<"$cg"
		cg_name="${cg_array[0]}"
		cg_cpus="${cg_array[1]}"
		cg_partition="${cg_array[2]}"

		if cgroupv2_exists "$cg_name"; then
			cgroupv2_remove "$cg_name"
		fi

		cgroupv2_create "$cg_name"
		cgroupv2_cpuset "$cg_name" "$cg_cpus"
		cgroupv2_partition "$cg_name" "$cg_partition"
	done
}

# ------------------------ PARAMETER MANAGEMENT ------------------------- #

function scheduler_detect {
	local kernel
	kernel=$(uname -r)

	case "$kernel" in
	*apedf*wf*)
		echo apedf-wf
		;;
	*apedf*)
		echo apedf-ff
		;;
	*)
		echo global
		;;
	esac
}

# ------------------------- GOVERNOR MANAGEMENT ------------------------- #

CPUFREQ_DIR="/sys/devices/system/cpu/cpu${CPUFREQ_CPU}/cpufreq"

function governor_detect() {
	cat "$CPUFREQ_DIR/scaling_governor"
}

function governor_maxfreq_detect() {
	cat "$CPUFREQ_DIR/scaling_max_freq"
}

function governor_set() {
	cpufreq-set -c "$CPUFREQ_CPU" -g "$governor"
	cpufreq-set -c "$CPUFREQ_CPU" -u "$CPUFREQ_MAXFREQ"khz
}

# ------------------------ EXPERIMENT MANAGEMENT ------------------------ #

SCHEDULERS=(
	global
	apedf-ff
	apedf-wf
)

GOVERNORS=(
	performance
	schedutil
)

TASKSETS_LOCATION="./tasksets"
KERNELS_LOCATION="./kernels"

function tasksets_get_all() {
	find "$TASKSETS_LOCATION" -name 'ts_*.json'
}

function basenames() {
	xargs -d '\n' -n1 basename
}

function tasksets_filter_ntask() {
	grep -E -o '_n[0-9]+_' | tr -d _n
}

function tasksets_filter_index() {
	grep -E -o '_i[0-9]+_' | tr -d _i
}

function tasksets_filter_utilization() {
	grep -E -o '_u[0-9]*\.[0-9]+\.json' | tr -d _u | sed 's#\.json##gi'
}

function tasksets_get_param_list() {
	tasksets_get_all | basenames | tasksets_filter_"$1" | sort -n | uniq
}

NTASKS=()
INDEXES=()
UTILIZATIONS=()

N_RUNS=0

function tasksets_fill_data() {
	if [ -z "${NTASKS[0]}" ]; then
		readarray -t NTASKS < <(tasksets_get_param_list ntask)
		readarray -t INDEXES < <(tasksets_get_param_list index)
		readarray -t UTILIZATIONS < <(tasksets_get_param_list utilization)
	fi
}

function calculate_n_runs() {
	echo "${#GOVERNORS[@]}" \
		'*' "${#SCHEDULERS[@]}" \
		'*' "${#NTASKS[@]}" \
		'*' "${#UTILIZATIONS[@]}" \
		'*' "${#INDEXES[@]}" | bc
}

function get_list() {
	tasksets_fill_data

	echo "${NTASKS[*]}"
	echo "${INDEXES[*]}"
	echo "${UTILIZATIONS[*]}"
}

function experiment_is_running() {
	# Experiments run in screens, so check if there is any screen
	# running called 'experiment'
	if screen -ls | cut -d. -f2 | tail -n +2 | cut -d$'\t' -f1 |
		grep -q experiment; then
		return 0
	fi
	return 1
}

function trim() {
	xargs
}

function get_progress() {
	# Parses current line searching for the current progress:
	local line="$1"
	line=$(echo "$line" | trim)
	if [ -z "$line" ] ||
		echo "$line" | grep -q 'command not found'; then
		echo ''
		return
	fi

	# If this line is shown, it's over
	if echo "$line" | grep -q 'All tests successful'; then
		echo 'END'
		return
	fi

	# If this line is shown, we have to restart the script
	if echo "$line" | grep -q 'Swapping kernel'; then
		echo 'RESTART'
		return
	fi

	# Otherwise we need to check whether there is a progress to display:
	local progress
	progress="$(echo "$line" | grep -E -o '\[[0-9]+/[0-9]+\]' || true)"
	if [ -n "$progress" ]; then
		echo "$progress"
		return
	fi

	# Check if it is clean up
	if echo "$line" | grep -q 'Cleaning'; then
		echo ''
		return
	fi
}

# Progress is expressed by a log file called last_experiment.log. The
# following are possible values for the progress (part of the last line,
# not the full line):
# - All tests successful: you are finished
# - Something went wrong: tests finished because of error
# - Swapping kernel: tests must be resumed after a reboot
# - [NN/MM]: current experiment progress
function experiment_check_progress() {
	local running=0
	local tmpfile
	local tmpfile2
	tmpfile=$(mktemp)
	tmpfile2=$(mktemp)

	if experiment_is_running; then
		running=1
	fi

	# Read progress file in reverse
	tail <"last_experiment.log" >"$tmpfile2"
	echo '' >>"$tmpfile2"
	tac "$tmpfile2" >"$tmpfile"

	local progress=''

	# Get first non-blank line
	local line
	while read -r line; do
		progress="$(get_progress "$line")"
		if [ -n "$progress" ]; then
			case "$progress" in
			END)
				echo END
				return 0
				;;
			RESTART)
				echo RESTART
				return 1
				;;
			*)
				if [ "$running" = 1 ]; then
					echo "$progress"
					return 0
				else
					echo RESTART
					return 1
				fi
				;;
			esac
		fi
	done <"$tmpfile"

	echo ERROR
	return 1
}

function experiment_start() {
	if experiment_is_running; then
		echo "Cannot start experiment: already running!" >&2
		return 1
	fi

	# Re-run self with the "run" command instead of "start"
	screen -L -Logfile last_experiment.log \
		-S experiment \
		-d -m \
		"$SCRIPT_PATH" run
}

# function experiment_start_if_rebooted() {
# 	if [ "$(experiment_check_progress || true)" = RESTART ] ; then
# 		experiment_start
# 	fi
# }

function power_meter_stuck_check() {
	local fname="$1"
	local stuck_check=

	# Power logs have CRLF line endings... sigh...
	stuck_check="$(sed 's/\r$//' <"$fname" | "$STUCK_CHECKER" -F,)"
	case "$stuck_check" in
	good)
		# What we want, cool, keep going
		return 0
		;;
	stuck)
		# Well, crap, stop and ask for the user intervention
		notify stuck
		echo "POWER METER IS STUCK! ABORTING!"
		return 1
		;;
	empty)
		# Even worse!!
		notify stuck empty
		echo "POWER METER IS EMPTY! ABORTING!"
		return 1
		;;
	*)
		# Parsing error
		echo "AWK PARSING ERROR! ABORTING!"
		return 1
		;;
	esac
}

function experiment_execute_taskset() {
	# Relevant variables:
	# - file_in: taskset json file
	# - dir_out: where to place the output of the experiment

	# Clean stuff from previous execution
	rm -f "$TMPDIR/"*
	mkdir -p "$TMPDIR/rt-app-logs"

	# Check that the temperature is low enough
	while ! therm_can_begin; do
		printf 'Cooling down... '
		# FIXME: put a maximum timeout, then reboot
		sleep 5
	done

	printf 'Starting... '

	# Turn tracing on
	echo 1 >/sys/kernel/tracing/tracing_on

	# Empty trace buffer
	echo >/sys/kernel/tracing/trace

	power_monitor_start
	therm_monitor_start

	# Run rtapp in the right cgroup
	cgroupv2_run "$CGROUP_TASKSETS" nice -n 20 \
		"$RTAPP" -t "$RTAPP_TIMEOUT" -l "$RTAPP_LOGLEVEL" "$file_in"

	power_monitor_stop
	therm_monitor_stop

	# Copy back trace buffer
	cat /sys/kernel/tracing/trace >"$TMPDIR/kernel.trace"
	echo 0 >/sys/kernel/tracing/tracing_on

	sleep 2s

	# Copy back results
	cp -a "$TMPDIR/rt-app-logs/"* "$dir_out"
	cp -a "$POWER_MONITOR_OUT" "$dir_out"
	cp -a "$THERM_MONITOR_OUT" "$dir_out"
	cp -a "$TMPDIR/kernel.trace" "$dir_out"

	sync
	echo 1 >/proc/sys/vm/drop_caches

	# Clean stuff from previous execution again, just in case
	rm -f "$TMPDIR/"*

	power_meter_stuck_check "$dir_out/power.log"

	printf 'DONE!'
}

function kernel_change() {
	# The required kernel is expressed by the $scheduler variable
	cp "$KERNELS_LOCATION"/"$scheduler".zImage /media/boot/zImage
}

function print_progress() {
	printf "+ [%0${print_width}d/%d] %s %s %s:" \
		"$cur_total_index" "$N_RUNS" "$scheduler" "$governor" "$taskset"
}

function experiment_run_step() {
	taskset="ts_n${ntask}_i${index}_u${utilization}"
	taskset_fname="${taskset}.json"
	file_in=$(find "${TASKSETS_LOCATION}" -type f -name "$taskset_fname" -print -quit || true)

	print_progress

	if [ -z "$file_in" ]; then
		printf 'No input file, skipping...'
		return 0
	fi

	# Input file exists
	dir_out="$OUTDIR/$scheduler/$governor/$taskset.out.d"

	if [ ! -d "$dir_out" ]; then
		mkdir -p "$dir_out"
	fi

	if [ -n "$(ls -A "$dir_out" 2>/dev/null)" ]; then
		printf 'Nonempty directory exists, skipping...'
		return 0
	fi

	# Directory is empty, we must run the experiment
	if [ "$(scheduler_detect)" != "$scheduler" ]; then
		# We must change kernel
		printf '%s\n' 'Swapping kernel!'
		kernel_change
		sleep 5
		sync

		notify reboot
		sleep 2

		reboot
	fi

	printf 'Must execute...'

	# The kernel is the right one, let's check that the governor is correct
	if [ "$(governor_detect)" != "$governor" ] || [ "$(governor_maxfreq_detect)" != "$CPUFREQ_MAXFREQ" ]; then
		governor_set
		sleep 2
	fi

	# We have the correct kernel and governor pair, time to start the experiment
	experiment_execute_taskset

	# We notify only on successful execution
	notify_progress "$cur_total_index" "$N_RUNS"
}

function experiment_run() {
	setup
	tasksets_fill_data
	N_RUNS="$(calculate_n_runs)"

	# Get the number of digits in N_RUNS
	local print_width=${#N_RUNS}

	cur_total_index=0
	for index in "${INDEXES[@]}"; do
		for governor in "${GOVERNORS[@]}"; do
			for scheduler in "${SCHEDULERS[@]}"; do
				for ntask in "${NTASKS[@]}"; do
					for utilization in "${UTILIZATIONS[@]}"; do
						cur_total_index=$((cur_total_index + 1))
						experiment_run_step
						printf '\n'
					done
				done
			done
		done
	done

	printf " + All tests successful!!\n"
	notify finish
}

# -------------------------------- MAIN --------------------------------- #

function cleanup() {
	last_result=$?
	trap - EXIT

	printf "Cleaning up..." >&2

	therm_monitor_stop || true
	power_monitor_stop || true

	if [ "$last_result" != 0 ]; then
		printf 'Something went wrong!!\n'
	fi

	if [ -d "$TMPDIR" ]; then
		rm -rf "${TMPDIR:?}/"*
		umount "$TMPDIR" || true
	fi

	if [ "$1" = EXIT ]; then
		return 0
	fi

	trap - "$1"
	kill -"$1" $BASHPID
}

function setup_cleanup() {
	trap 'cleanup EXIT' EXIT
	trap 'cleanup HUP' HUP
	trap 'cleanup TERM' TERM
	trap 'cleanup INT' INT
}

function isolate_rescue_ssh() {
	# Hangs after a while, but always succeeds in my experience, so we
	# put a timeout of 10 seconds, just in case
	timeout 10 systemctl isolate rescue-ssh || true
}

function setup_ramfs() {
	mkdir -p "$TMPDIR"
	if mountpoint -q -- "$TMPDIR"; then
		# Already mounted, cool
		return
	fi

	# Check whether there is an entry in fstab for TMPDIR
	if ! grep -q -F "$TMPDIR" /etc/fstab; then
		# Entry does not exist, add it:
		echo "none \"$TMPDIR\" ramfs noauto,user,size=1Gi,mode=1777 0 0" >>/etc/fstab
	fi

	mount "$TMPDIR"
}

function setup() {
	TMPDIR=/mnt/ramfs
	setup_cleanup
	setup_ramfs
	THERM_MONITOR_OUT="$TMPDIR/therm.log"
	POWER_MONITOR_OUT="$TMPDIR/power.log"
	cgroupv2_create_all
	if [ -n "$RTLIMIT" ]; then
		echo + Setting kernel.sched_rt_runtime_us="$RTLIMIT"
		sysctl -w kernel.sched_rt_runtime_us="$RTLIMIT" >/dev/null
	fi
	isolate_rescue_ssh
}

function main() {
	# SCRIPT_NAME="$(basename "${BASH_SOURCE[0]}")"
	SCRIPT_PATH="$(realpath "${BASH_SOURCE[0]}")"
	SCRIPT_DIR="$(realpath "$(dirname "$SCRIPT_PATH")")"

	PROJ_PATH="$(realpath "$SCRIPT_DIR"/..)"
	TEST_PATH="$(realpath "$PROJ_PATH"/test)"
	HELPERS_PATH="$(realpath "$TEST_PATH/scripts/execution")"
	APPS_PATH="$PROJ_PATH/test/apps"
	RTAPP="$APPS_PATH/rt-app/src/rt-app"
	SERIAL_LOGGER="$HELPERS_PATH/slogger.py"
	NOTIFIER="$HELPERS_PATH/notifier.py"
	STUCK_CHECKER="$HELPERS_PATH/powerstuck.awk"

	# Move to the correct directory
	cd "$TEST_PATH"

	case "$1" in
	check_progress)
		experiment_check_progress
		;;
	start)
		experiment_start
		;;
	# start_if_rebooted)
	# 	experiment_start_if_rebooted
	# 	;;
	run)
		experiment_run
		;;
	*)
		echo "Unsupported command: $1" >&2
		echo "Supported commands: start, check_progress." >&2
		echo "Commands accepted for internal use only: run." >&2
		return 1
		;;
	esac
}

(
	set -e
	main "$@"
)
