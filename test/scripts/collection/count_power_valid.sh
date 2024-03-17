#!/bin/bash

function count_tuples() {
awk '
	function print_tuple() {
		if (a == -1)
			return;
		printf("(%s %s %s) => %d (%s)\n", a, b, c, count, list);
	}
	BEGIN { a=-1; b=-1; c=-1; list=""; }
	{
		if (a == $4 && b == $5 && c == $6) {
		} else {
			list = list ""
			print_tuple();
			a = $4;
			b = $5;
			c = $6;
			count = 0;
			list = ""
		}
		count++;
		list = list $1 "+" $2 ","
	}
	END {
		print_tuple();
	}
'
}

(
	set -e
	grep NOT "$1" | sed 's/^.*apedf-//g' | sed 's/^.*global/global/g' | sed 's/power.log//g' | sed 's/.out.d//g' |
		tr '_' ' ' | tr '/' ' ' | tr -s ' ' | cut -d' ' -f1-6 | sort -k4 -k5 -k6 | count_tuples # | sort -k5 -nr
)
