#!/bin/bash

SCRIPT_NAME=$(basename "${BASH_SOURCE[0]}")
SCRIPT_PATH=$(realpath "$(dirname "${BASH_SOURCE[0]}")")
PROJ_PATH=$(realpath "$SCRIPT_PATH/..")

APPS_PATH="$PROJ_PATH/apps"
RTAPP_DIR="$APPS_PATH/rt-app/"
RTAPP="$APPS_PATH/rt-app/src/rt-app"

function usage() {
	echo "
Usage: ${SCRIPT_NAME} <options>

    --skipbuild         - skips the build of the apps (e.g., rtapp)
    --printlist         - print the full ordered list of tasksets

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
    --maxfreq=MAXFREQ   - maximum frequency to set (using 'performance'
                          governor), value expressed either in Hz or by using
                          unit suffixes (e.g., 1.4GHz); by default, the maximum
                          frequency accepted by core 0 is used
                          (in this case, $MAX_FREQ_DEFAULT HZ)

    -h --help           - show this help message and exit
    --debug             - run this program in debug mode
"
}

MAX_FREQ_DEFAULT="$(cpufreq-info --hwlimits | cut -d' ' -f2)"

function parse_args() {
	# Put options initializations here
	TASKSDIR="$(realpath .)"
	OUTDIR="$(realpath .)/out"
	LOGLEVEL=10
	RTLIMIT=
	COOLDOWN=90s
	SKIPBUILD=n
	PRINTLIST=n
	MAX_FREQ="$MAX_FREQ_DEFAULT"
	while [ $# -gt 0 ]; do
		case $1 in
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
		--loglevel*)
			if echo $1 | grep '=' >/dev/null; then
				LOGLEVEL=$(echo $1 | sed 's/^--loglevel=//')
			elif [ -n "$2" ]; then
				LOGLEVEL=$2
				shift
			else
				echo "${SCRIPT_NAME}: Error - '--loglevel' expects an argument"
				usage
				return 1
			fi
			;;
		--tasksdir*)
			if echo $1 | grep '=' >/dev/null; then
				TASKSDIR=$(echo $1 | sed 's/^--tasksdir=//')
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
			if echo $1 | grep '=' >/dev/null; then
				OUTDIR=$(echo $1 | sed 's/^--outdir=//')
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
			if echo $1 | grep '=' >/dev/null; then
				RTLIMIT=$(echo $1 | sed 's/^--rtlimit=//')
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
			if echo $1 | grep '=' >/dev/null; then
				COOLDOWN=$(echo $1 | sed 's/^--cooldown=//')
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
			if echo $1 | grep '=' >/dev/null; then
				MAXFREQ=$(echo $1 | sed 's/^--maxfreq=//')
			elif [ -n "$2" ]; then
				MAXFREQ=$2
				shift
			else
				echo "${SCRIPT_NAME}: Error - '--maxfreq' expects an argument"
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
	if [ $LOGLEVEL -ge 0 ] && [ $LOGLEVEL -le 10 ]; then
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
	source "$SCRIPT_PATH/util/telegram-tokens.sh" 2>/dev/null || true
	source "$SCRIPT_PATH/util/telegram.sh"

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
	telegram_notify "Experiment on $(hostname_waddress) terminated!"

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
	RUID=$(id -ru)
	RGID=$(id -rg)

	if [ "$SKIPBUILD" != y ]; then
		echo " + Re-building apps (just in case) ..."
		"$SCRIPT_PATH/util/apps-builder.sh" --clean "$APPS_PATH" all
	fi

	# Get the list of all tasksets
	tsets=($(get_all_tsets "$TASKSDIR"))
	ntsets="${#tsets[@]}"

	if [ "$ntsets" -lt 1 ] ; then
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

	# Assuming that all cpus are used
	cpu_set=0-$(($(nproc) - 1))

	# Adjust CPU frequency
	echo " + setting maximum frequency and governor..."
	cpufreq-set -c "$cpu_set" --governor performance
	cpufreq-set -c "$cpu_set" --max "$MAX_FREQ"
	echo " + advertised frequency configuration: "
	cpufreq-info -o --human

	i=0
	j=10

	# Disable deadline admission control or change its bound
	if [ -n "$RTLIMIT" ]; then
		echo " + Setting kernel.sched_rt_runtime_us='$RTLIMIT'"
		sysctl -w kernel.sched_rt_runtime_us="$RTLIMIT"
	fi

	echo ''
	echo ' + Starting tests...'
	echo ''

	for ts in "${tsets[@]}"; do
		i=$((i + 1))
		printf ' + Running test [%0'$ndigits'd/%0'$ndigits'd] defined in %s ...' "$i" "$ntsets" "$ts"

		# Power sampler
		# nice -n -20 "$SAMPLER_APP" >"$POWER_FILE" 2>/dev/null &
		# POWER_PID="$!"
		# sleep 2s

		nice -n 20 "$RTAPP" -l "$LOGLEVEL" "$ts"
		sleep 2s

		# kill "$POWER_PID"
		sync
		wait

		ts_base="$(basename "$ts")"
		ts_base="${ts_base%.*}"
		power_file_out="${ts_base}.power"
		rtapp_dir_out="${ts_base}.rt-app.d"

		# cp "$POWER_FILE" "${OUTDIR}/${power_file_out}"
		cp -r "/tmp/rt-app-logs" "${OUTDIR}/${rtapp_dir_out}"

		# chown -R "${ruid}:${rgid}" "${OUTDIR}/${power_file_out}"
		chown -R "${ruid}:${rgid}" "${OUTDIR}/${rtapp_dir_out}"

		echo ' + DONE! Cooling down for a bit...'
		# Memory caches tend to fill up rather quickly, let's avoid that
		sync
		echo 1 >/proc/sys/vm/drop_caches

		# Wait for a while just in case board is heating up
		sleep "$COOLDOWN"

		if [ $i = $j ]; then
			telegram_notify \
				"Completion rate on $(hostname_waddress): $i / $ntsets" || true
			j=$((j + 10))
		fi

	done

	echo ' + All tests successful!!! '

	telegram_notify "Experiment on $(hostname_waddress) was a success!"
	# rm "${POWER_FILE}"
}

(
	set -e
	main "$@"
)