#!/usr/bin/awk -f

# Prints if the output of the file is "stuck" for a long while.
# Output is considered "stuck" if more than 10% of its duration is
# comprised of the same value without any change.

# Input is a TSV file in which there is no header and the column indicated
# by MY_COLUMN is the key field

function argmax(array,   i, max, imax) {
	max=-1;
	imax=-1;
	for (i in array) {
		if (array[i] > max) {
			max = array[i];
			imax = i;
		}
	}

	return imax;
}

BEGIN {
	last = -1;
	count = 0;
	MY_COLUMN = 8;
	skipped=0;
}

NF != 17 {
	# All lines with a number different than 17 fields are skipped
	printf("NF != 17 => %d\n", NF) > "/dev/stderr";
	skipped++;
	next;
}

{
	current = $MY_COLUMN;
	if (current != last) {
		# Value is no longer stuck
		if (maxes[last] < count && last >= 0) {
			maxes[last] = count;
		}
		last = current;
		count = 0;
	}
	count++;
}

END {
	current = $MY_COLUMN;
	if (maxes[last] < count)
		maxes[last] = count;
	last = current;

	# printarray(maxes)

	imax = argmax(maxes);
	count = maxes[imax];

	if (skipped == NR && NR > 0) {
		printf("skipped all lines!\n") > "/dev/stderr";
	}

	if (NR < 10 || imax == -1) {
		printf("empty\n");
	} else if ((count / NR) >= .10) {
		printf("stuck\n");
	} else {
		printf("good\n");
	}
}
