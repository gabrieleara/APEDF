#!/usr/bin/awk -E

# Prints 1 if the output of the file is "stuck" for a long while.
# Output is considered "stuck" if more than 10% of its duration is
# comprised of the same value without any change.

# Input is a TSV file in which there is no header and the 4th column is the
# key field


/NOT/ { good++ }
/EMPTY/ { empty++ }
END {
	stuck = NR - empty - good;
	printf("empty      stuck      good       total\n");
	printf("%-10d %-10d %-10d %-10d\n", empty, stuck, good, NR);
}
