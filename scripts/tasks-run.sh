#!/bin/bash

SCRIPT_NAME=$(basename "${BASH_SOURCE[0]}")
SCRIPT_PATH=$(realpath "$(dirname "${BASH_SOURCE[0]}")")
PROJ_PATH=$(realpath "$SCRIPT_PATH/..")

APPS_PATH="$PROJ_PATH/apps"
# RTAPP_DIR="$APPS_PATH/rt-app/"
RTAPP="$APPS_PATH/rt-app/src/rt-app"

function usage() {
	echo "
Usage: ${SCRIPT_NAME} <options>

    --skipbuild         - skips the build of the apps (e.g., rtapp)
    --printlist         - print the full ordered list of tasksets

    --timeout=TIMEOUT   - the timeout for rt-app, values greater than zero
                          indicate how much rt-app should run for.
                          (default = -1, aka: use value from each JSON file)
    --tasksdir=TASKSDIR - the directory where to look for tasksets; it will
                          look only for tasksets in that directory, meaning
                          no subdirectories!
                          (default = CWD)
    --outdir=OUTDIR     - the directory where to put all output files
                          (default = CWD/out)
    --loglevel=LOGLEVEL - the log level to use when running rt-app
                          (default = 10)
    --rtlimit=RTLIMIT   - value to write in 'kernel.sched_rt_runtime_us'; use -1
                          to disable the runtime limit for rt apps
                          (default: no value will be written)
    --cooldown=SECONDS  - time to sleep for in-between runs for cooldown
                          (default: 90s)
    --turnoff=CORELIST  - a SPACE SEPARATED list of cores (single string) to
                          turn off (default: empty, no cores will be turned off)
    --corelist=CORELIST - a TASKSET-LIKE list of cores to use; affects:
                          --maxfreq (only the max freq of these cores will be changed)
                          --governor (only the freq governor of these cores will be changed)
                          (default: all the cores on the platform, $CORELIST_DEFAULT)
    --maxfreq=MAXFREQ   - maximum frequency to set (using 'performance'
                          governor), value expressed either in Hz or by using
                          unit suffixes (e.g., 1.4GHz); by default, the maximum
                          frequency accepted by core 0 is used
                          (in this case, $MAXFREQ_DEFAULT kHZ)
    --governor=GOVERNOR - the frequency governor to use (default: no governor changed)

    -h --help           - show this help message and exit
    --debug             - run this program in debug mode
"
}

MAXFREQ_DEFAULT="$(cpufreq-info --hwlimits | cut -d' ' -f2)"
CORELIST_DEFAULT=0-$(($(nproc) - 1))

function parse_args() {
	# Put options initializations here
	TASKSDIR="$(realpath .)"
	OUTDIR="$(realpath .)/out"
	LOGLEVEL=10
	RTLIMIT=
	COOLDOWN=90s
	SKIPBUILD=n
	PRINTLIST=n
	OVERWRITE=n
	TIMEOUT=-1
	TURNOFF=""
	CORELIST="$CORELIST_DEFAULT"
	GOVERNOR=performance
	MAXFREQ="$MAXFREQ_DEFAULT"
	while [ $# -gt 0 ]; do
		case "$1" in
		--debug)
			set -x
			;;
		-h | --help)
			usage
			return 1
			;;
		--skipbuild)
			SKIPBUILD=y
			;;
		--printlist)
			PRINTLIST=y
			;;
		--overwrite)
			OVERWRITE=y
			;;
		--loglevel*)
			if echo "$1" | grep '=' >/dev/null; then
				LOGLEVEL=$(echo "$1" | sed 's/^--loglevel=//')
			elif [ -n "$2" ]; then
				LOGLEVEL=$2
				shift
			else
				echo "${SCRIPT_NAME}: Error - '--loglevel' expects an argument"
				usage
				return 1
			fi
			;;
		--timeout*)
			if echo "$1" | grep '=' >/dev/null; then
				TIMEOUT=$(echo "$1" | sed 's/^--timeout=//')
			elif [ -n "$2" ]; then
				TIMEOUT=$2
				shift
			else
				echo "${SCRIPT_NAME}: Error - '--timeout' expects an argument"
				usage
				return 1
			fi
			;;
		--tasksdir*)
			if echo "$1" | grep '=' >/dev/null; then
				TASKSDIR=$(echo "$1" | sed 's/^--tasksdir=//')
			elif [ -n "$2" ]; then
				TASKSDIR=$2
				shift
			else
				echo "${SCRIPT_NAME}: Error - '--tasksdir' expects an argument"
				usage
				return 1
			fi
			;;
		--outdir*)
			if echo "$1" | grep '=' >/dev/null; then
				OUTDIR=$(echo "$1" | sed 's/^--outdir=//')
			elif [ -n "$2" ]; then
				OUTDIR=$2
				shift
			else
				echo "${SCRIPT_NAME}: Error - '--outdir' expects an argument"
				usage
				return 1
			fi
			;;
		--rtlimit*)
			if echo "$1" | grep '=' >/dev/null; then
				RTLIMIT=$(echo "$1" | sed 's/^--rtlimit=//')
			elif [ -n "$2" ]; then
				RTLIMIT=$2
				shift
			else
				echo "${SCRIPT_NAME}: Error - '--rtlimit' expects an argument"
				usage
				return 1
			fi
			;;
		--cooldown*)
			if echo "$1" | grep '=' >/dev/null; then
				COOLDOWN=$(echo "$1" | sed 's/^--cooldown=//')
			elif [ -n "$2" ]; then
				COOLDOWN=$2
				shift
			else
				echo "${SCRIPT_NAME}: Error - '--cooldown' expects an argument"
				usage
				return 1
			fi
			;;
		--maxfreq*)
			if echo "$1" | grep '=' >/dev/null; then
				MAXFREQ=$(echo "$1" | sed 's/^--maxfreq=//')
			elif [ -n "$2" ]; then
				MAXFREQ=$2
				shift
			else
				echo "${SCRIPT_NAME}: Error - '--maxfreq' expects an argument"
				usage
				return 1
			fi
			;;
		--governor*)
			if echo "$1" | grep '=' >/dev/null; then
				GOVERNOR=$(echo "$1" | sed 's/^--governor=//')
			elif [ -n "$2" ]; then
				GOVERNOR=$2
				shift
			else
				echo "${SCRIPT_NAME}: Error - '--governor' expects an argument"
				usage
				return 1
			fi
			;;
		--corelist*)
			if echo "$1" | grep '=' >/dev/null; then
				CORELIST=$(echo "$1" | sed 's/^--corelist=//')
			elif [ -n "$2" ]; then
				CORELIST=$2
				shift
			else
				echo "${SCRIPT_NAME}: Error - '--corelist' expects an argument"
				usage
				return 1
			fi
			;;
		--turnoff*)
			if echo "$1" | grep '=' >/dev/null; then
				TURNOFF=$(echo "$1" | sed 's/^--turnoff=//')
			elif [ -n "$2" ]; then
				TURNOFF=$2
				shift
			else
				echo "${SCRIPT_NAME}: Error - '--turnoff' expects an argument"
				usage
				return 1
			fi
			;;
		*)
			echo "${SCRIPT_NAME}: Error - Unexpected argument ${1}" >&2
			usage
			return 1
			;;
		esac
		shift
	done
}

function check_loglevel() {
	if [ "$LOGLEVEL" -ge 0 ] && [ "$LOGLEVEL" -le 10 ]; then
		return 0
	fi

	echo "${SCRIPT_NAME}: Error - LOGLEVEL must be between 0 and 10" >&2
	usage
	return 1
}

function hostname_waddress() {
	echo "$(hostname) ($(hostname -I | cut -d' ' -f1))"
}

# Prints the complete list of JSON files in TASKSDIR,
# each containing a taskset
function get_all_tsets() {
	local path="$(realpath "$TASKSDIR")"
	local pathlen="${#path}"
	local f1=$((pathlen + 5))
	local f2=$((pathlen + 13))
	local f3=$((pathlen + 9))

	find "$path" -maxdepth 1 -name 'ts_n*_i*_u*.json' |
		sort -k 1."$f1"n -k 1."$f2"nr -k 1."$f3"n
}

function setup() {
	POWER_FILE=$(mktemp)
	POWER_PID=

	trap 'cleanup EXIT' EXIT
	trap 'cleanup HUP' HUP
	trap 'cleanup TERM' TERM
	trap 'cleanup INT' INT
}

function cleanup() {
	trap - EXIT

	kill "$POWER_PID" 2>/dev/null || true
	rm -f "$POWER_FILE" 2>/dev/null || true

	if [ "$1" = EXIT ]; then
		return 0
	fi

	trap - "$1"
	kill -"$1" $BASHPID
}

function main() {
	setup
	parse_args "$@"
	check_loglevel

	if [ "$(id -u)" != 0 ]; then
		echo "This script must be run as root (or with sudo)" >&2
		return 1
	fi
	ruid=$(id -ru)
	rgid=$(id -rg)

	if [ "$SKIPBUILD" != y ]; then
		echo " + Re-building apps (just in case) ..."
		"$SCRIPT_PATH/util/apps-builder.sh" --clean "$APPS_PATH" all
	fi

	# Get the list of all tasksets
	tsets=($(get_all_tsets "$TASKSDIR"))
	ntsets="${#tsets[@]}"

	if [ "$ntsets" -lt 1 ]; then
		echo "$SCRIPT_NAME: Error - invalid --tasksdir directory '$TASKSDIR'" >&2
		usage
		return 1
	fi

	if [ "$PRINTLIST" = y ]; then
		echo " + Following is the full ordered list of tasksets: "
		printf '%s\n' "${tsets[@]}"
		echo ''
	fi

	ndigits=${#ntsets}

	# Making the rt-app log directory and output one
	mkdir -p /tmp/rt-app-logs
	mkdir -p "$OUTDIR"

	# Turn off the given CPUs
	if [ -n "$TURNOFF" ]; then
		for c in $TURNOFF; do
			echo " + turning off cpu $c"
			echo 0 | tee "/sys/devices/system/cpu/cpu$c/online" >/dev/null
		done
	fi

	# Make changes to CPUFREQ configuration
	if [ -n "$MAXFREQ" ]; then
		echo " + setting maximum frequency..."
		cpufreq-set -c "$CORELIST" --max "$MAXFREQ"
	fi

	if [ -n "$GOVERNOR" ]; then
		echo " + setting frequency governor..."
		cpufreq-set -c "$CORELIST" --governor "$GOVERNOR"
	fi

	echo " + advertised frequency configuration: "
	cpufreq-info -o --human

	# Disable deadline admission control or change its bound
	if [ -n "$RTLIMIT" ]; then
		echo " + Setting kernel.sched_rt_runtime_us='$RTLIMIT'"
		sysctl -w kernel.sched_rt_runtime_us="$RTLIMIT"
	fi

	echo ''
	echo ' + Starting tests...'
	echo ''

	i=0
	for ts in "${tsets[@]}"; do
		i=$((i + 1))
		printf ' + Running test [%0'"$ndigits"'d/%0'"$ndigits"'d] defined in %s ...' "$i" "$ntsets" "$ts"

		ts_base="$(basename "$ts")"
		ts_base="${ts_base%.*}"
		# power_file_out="${ts_base}.power"
		rtapp_dir_out="${ts_base}.rt-app.d"

		if [ -d "${OUTDIR}/${rtapp_dir_out}" ] && [ "$OVERWRITE" != y ]; then
			echo ' ++ Skipping...'
			continue
		fi

		# Clean stuff from previous execution
		rm -f /tmp/rt-app-logs/*

		# Power sampler
		# nice -n -20 "$SAMPLER_APP" >"$POWER_FILE" 2>/dev/null &
		# POWER_PID="$!"
		# sleep 2s

		# Turn tracing on
		echo '1' > /sys/kernel/tracing/tracing_on

		# Empty trace buffer
		echo > /sys/kernel/tracing/trace

		nice -n 20 "$RTAPP" -t "$TIMEOUT" -l "$LOGLEVEL" "$ts"
		sleep 2s

		# Copy content of trace buffer in the rt-app logs directory, to
		# keep together with the logs
		cat /sys/kernel/tracing/trace > /tmp/rt-app-logs/kernel.trace

		# kill "$POWER_PID"
		sync
		wait

		# Delete all previous results first, to overwrite with the new ones
		if [ -d "${OUTDIR}/${rtapp_dir_out}" ]; then
			rm -rf "${OUTDIR:?}/${rtapp_dir_out}"
		fi

		# cp "$POWER_FILE" "${OUTDIR}/${power_file_out}"
		cp -r "/tmp/rt-app-logs" "${OUTDIR}/${rtapp_dir_out}"

		# chown -R "${ruid}:${rgid}" "${OUTDIR}/${power_file_out}"
		chown -R "${ruid}:${rgid}" "${OUTDIR}/${rtapp_dir_out}"

		echo ' + DONE! Cooling down for a bit...'
		# Memory caches tend to fill up rather quickly, let's avoid that
		sync
		echo 1 >/proc/sys/vm/drop_caches

		# Clean stuff from previous execution
		rm -f /tmp/rt-app-logs/*

		# Wait for a while just in case board is heating up
		sleep "$COOLDOWN"
	done

	echo ' + All tests successful!!! '
	# rm "${POWER_FILE}"
}

(
	set -e
	main "$@"
)
