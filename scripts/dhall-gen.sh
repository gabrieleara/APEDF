#!/bin/bash

function get_script_path() {
    echo "$(realpath "$(dirname "$(realpath "${BASH_SOURCE[0]}")")")"
}

function main() {
        local base="$1"
        if [ base == '' ]; then
                base="."
        fi

        for period in $(seq 500 100 900); do
                echo "$period"

                dperiod=$((period + 10))
                drun=$(echo "$dperiod * 0.945" | bc -l)

                lperiod="$period"
                lrun=$(echo "$lperiod / 10"   | bc -l)

                ratio=1000

                dperiod=$( echo "$dperiod * $ratio" | bc -l)
                drun=$(    echo "$drun * $ratio"    | bc -l)
                lperiod=$( echo "$lperiod * $ratio" | bc -l)
                lrun=$(    echo "$lrun * $ratio"    | bc -l)

                drun=$(echo "$drun / 1" | bc )
                lrun=$(echo "$lrun / 1" | bc )

                text_file=$base/$period.txt
                json_file=$base/$period.json

                for i in 0 1 2 3; do
                        echo $lrun $lperiod
                done >$text_file
                echo $drun $dperiod >>$text_file

                SDIR="$(get_script_path)"
                "$SDIR/util/taskset2json.py" \
                    -c "92" \
                    -r "1.0" \
                    -q "3.8" \
                    -R "2000" \
                    -T \
                    <"$text_file" >"$json_file"
                #     -r "$GT_RT_FRACTION" \
                #     -m "$GT_RT_MIN_DURATION" \
                #     -M "$GT_RT_MAX_DURATION" \
                #     -q "$max_quota" \
        done
}

(
        set -e
        main "$@"
)
