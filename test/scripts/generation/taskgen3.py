#!/usr/bin/env python3

"""\
A taskset generator for experiments with real-time task sets

Copyright 2010 Paul Emberson, Roger Stafford, Robert Davis.
All rights reserved.

Redistribution and use in source and binary forms, with or without
modification, are permitted provided that the following conditions are met:

   1. Redistributions of source code must retain the above copyright notice,
      this list of conditions and the following disclaimer.

   2. Redistributions in binary form must reproduce the above copyright notice,
      this list of conditions and the following disclaimer in the documentation
      and/or other materials provided with the distribution.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS ``AS IS'' AND ANY EXPRESS
OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES
OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO
EVENT SHALL THE AUTHORS OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT,
INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT
LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA,
OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF
LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE
OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF
ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

The views and conclusions contained in the software and documentation are
those of the authors and should not be interpreted as representing official
policies, either expressed or implied, of Paul Emberson, Roger Stafford or
Robert Davis.

Includes Python implementation of Roger Stafford's randfixedsum implementation
http://www.mathworks.com/matlabcentral/fileexchange/9700
Adapted specifically for the purpose of taskset generation with fixed
total utilisation value

Please contact paule@rapitasystems.com or robdavis@cs.york.ac.uk if you have
any questions regarding this software.
"""


import argparse
import sys
import os
import textwrap
import random
import numpy as np


def StaffordRandFixedSum(n, u, nsets):
    # deal with n=1 case
    if n == 1:
        return np.tile(np.array([u]), [nsets, 1])

    k = np.floor(u)
    s = u
    step = 1 if k < (k - n + 1) else -1
    s1 = s - np.arange(k, (k - n + 1) + step, step)
    step = 1 if (k + n) < (k - n + 1) else -1
    s2 = np.arange((k + n), (k + 1) + step, step) - s

    tiny = np.finfo(float).tiny
    huge = np.finfo(float).max

    w = np.zeros((n, n + 1))
    w[0, 1] = huge
    t = np.zeros((n - 1, n))

    for i in np.arange(2, (n + 1)):
        tmp1 = w[i - 2, np.arange(1, (i + 1))] * s1[np.arange(0, i)] / float(i)
        tmp2 = w[i - 2, np.arange(0, i)] * s2[np.arange((n - i), n)] / float(i)
        w[i - 1, np.arange(1, (i + 1))] = tmp1 + tmp2
        tmp3 = w[i - 1, np.arange(1, (i + 1))] + tiny
        tmp4 = np.array((s2[np.arange((n - i), n)] > s1[np.arange(0, i)]))
        t[i - 2, np.arange(0, i)] = (tmp2 / tmp3) * tmp4 + (1 - tmp1 / tmp3) * (np.logical_not(tmp4))

    m = nsets
    x = np.zeros((n, m))
    rt = np.random.uniform(size=(n - 1, m))  # rand simplex type
    rs = np.random.uniform(size=(n - 1, m))  # rand position in simplex
    s = np.repeat(s, m)
    j = np.repeat(int(k + 1), m)
    sm = np.repeat(0, m)
    pr = np.repeat(1, m)

    for i in np.arange(n - 1, 0, -1):  # iterate through dimensions
        e = (rt[(n - i) - 1, ...] <= t[i - 1, j - 1])  # decide which direction to move in this dimension (1 or 0)
        sx = rs[(n - i) - 1, ...] ** (1 / float(i))  # next simplex coord
        sm = sm + (1 - sx) * pr * s / float(i + 1)
        pr = sx * pr
        x[(n - i) - 1, ...] = sm + pr * e
        s = s - e
        j = j - e  # change transition table column if required

    x[n - 1, ...] = sm + pr * s

    # iterated in fixed dimension order but needs to be randomised
    # permute x row order within each column
    for i in range(0, m):
        x[..., i] = x[np.random.permutation(n), i]

    return np.transpose(x)


def gen_periods(n, nsets, min, max, gran, dist):
    if dist == "logunif":
        periods = np.exp(np.random.uniform(low=np.log(min), high=np.log(max + gran), size=(nsets, n)))
    elif dist == "unif":
        periods = np.random.uniform(low=min, high=(max + gran), size=(nsets, n))
    else:
        return None
    periods = np.floor(periods / gran) * gran

    return periods


def print_taskset(taskset, format):
    for t in range(np.size(taskset, 0)):
        data = {'Ugen': taskset[t][0], 'U': taskset[t][1], 'T': taskset[t][2], 'C': taskset[t][3]}
        print(format % data)


def gen_tasksets(options):
    x = StaffordRandFixedSum(options.n, options.util, options.nsets)
    periods = gen_periods(options.n, options.nsets, options.permin, options.permax, options.pergran, options.perdist)
    # iterate through each row (which represents utils for a taskset)
    for i in range(np.size(x, axis=0)):
        C = x[i] * periods[i]
        for j in range(np.size(C, axis=0)):
            if C[j] < 1200:
                C[j] = C[j] + random.randint(1000, 1500)
                periods[i][j] = C[j] / x[i][j]
                periods[i][j] = np.round(periods[i][j]/options.pergran, decimals=0)*options.pergran
                C[j] = x[i][j] * periods[i][j]

        if options.round_C:
            C = np.round(C, decimals=0)

        taskset = np.c_[x[i], C / periods[i], periods[i], C]

        print_taskset(taskset, options.format)
        if i < np.size(x, axis=0) - 1:
            print("")


def escape_format_string(string: str):
    return string.replace('%', '%%').replace('\\', '\\\\')


def wrap_string(string: str):
    return f"'{string}'"


class RawDescriptionDefaultHelpFormatter(
    argparse.RawTextHelpFormatter, argparse.ArgumentDefaultsHelpFormatter
):
    pass


def main():
    program_name = os.path.basename(sys.argv[0])

    description_str = textwrap.dedent(f"""\
        This is a taskset generator intended for generating data for experiments
        with real-time schedulability tests and design space exploration tools.

        The utilisation generation is done using Roger Stafford's randfixedsum algorithm.

        A paper describing this tool was published at the WATERS 2010 workshop.
        Copyright 2010 Paul Emberson, Roger Stafford, Robert Davis.
        All rights reserved.

        Run {program_name} --about for licensing information.
    """)

    # don't add help option as we will handle it ourselves
    parser = argparse.ArgumentParser(
        prog=program_name,
        description=description_str,
        add_help=True,
        formatter_class=RawDescriptionDefaultHelpFormatter,
        epilog=textwrap.dedent(
            f"""\
        examples:

            Generate 5 tasksets of 10 tasks with loguniform periods
            between 1000 and 100000.  Round execution times and output
            a table of execution times and periods.

                {program_name} -s 5 -n 10 -p 1000 -q 100000 -d logunif --round-C -f \"%(C)d %(T)d\\n\"

            Print utilisation values from Stafford's randfixedsum
            for 20 tasksets of 8 tasks, with one line per taskset,
            rounded to 3 decimal places:

                {program_name} -s 20 -n 8 -f \"%(Ugen).3f\"
        """),
    )

    parser.add_argument("--about", action="store_true", dest="about",
                        default=False,
                        help="See licensing and other information about this software")

    parser.add_argument("-u", "--taskset-utilisation",
                        metavar="UTIL", type=float, dest="util",
                        default="0.75",
                        help="Set total taskset utilisation to UTIL")
    parser.add_argument("-n", "--num-tasks",
                        metavar="N", type=int, dest="n",
                        default="5",
                        help="Produce tasksets of size N")
    parser.add_argument("-s", "--num-sets",
                        metavar="SETS", type=int, dest="nsets",
                        default="3",
                        help="Produce SETS tasksets")
    parser.add_argument("-S", "--seed",
                        metavar="SEED", type=int, dest="seed",
                        default="0",
                        help="Set the random number generator seed")
    parser.add_argument("-d", "--period-distribution",
                        metavar="PDIST", type=str, dest="perdist",
                        default="logunif",
                        help="Choose period distribution to be 'unif' or 'logunif'")
    parser.add_argument("-p", "--period-min",
                        metavar="PMIN", type=int, dest="permin",
                        default="1000",
                        help="Set minimum period value to PMIN")
    parser.add_argument("-q", "--period-max",
                        metavar="PMAX", type=int, dest="permax",
                        default=None,
                        help="Set maximum period value to PMAX [PMIN]")
    parser.add_argument("-g", "--period-gran",
                        metavar="PGRAN", type=int, dest="pergran",
                        default=None,
                        help="Set period granularity to PGRAN [PMIN]")

    parser.add_argument("--round-C", action="store_true", dest="round_C",
                        default=False,
                        help="Round execution times to nearest integer")

    format_help = textwrap.dedent("""\
        Specify output format as a Python templace string.
        The following variables are available:
            Ugen - the task utilisation value generated by Stafford's randfixedsum algorithm,
            T    - the generated task period value,
            C    - the generated task execution time,
            U    - the actual utilisation equal to C/T which will differ from Ugen if the --round-C option is used.
        See below for further examples.
        A new line is always inserted between tasksets.
    """)

    parser.add_argument("-f", "--output-format",
                        metavar="FORMAT", type=str, dest="format",
                        default='%(Ugen)f %(U)f %(C).2f %(T)d\\n',
                        help=format_help)

    args = parser.parse_args()

    if args.about:
        print(__doc__)
        return 0

    if args.n < 1:
        print("Minimum number of tasks is 1", file=sys.stderr)
        return 1

    if args.util > args.n:
        print("Taskset utilisation must be less than or equal to number of tasks", file=sys.stderr)
        return 1

    if args.nsets < 1:
        print("Minimum number of tasksets is 1", file=sys.stderr)
        return 1

    if args.seed > 0:
        # print("Setting the seed to " + str(args.seed), file=sys.stderr)
        np.random.seed(args.seed)

    known_perdists = ["unif", "logunif"]
    if args.perdist not in known_perdists:
        print("Period distribution must be one of " + str(known_perdists), file=sys.stderr)
        return 1

    if args.permin <= 0:
        print("Period minimum must be greater than 0", file=sys.stderr)
        return 1

    # permax = None is default.  Set to permin in this case
    if args.permax is None:
        args.permax = args.permin

    if args.permin > args.permax:
        print("Period maximum must be greater than or equal to minimum", file=sys.stderr)
        return 1

    # pergran = None is default.  Set to permin in this case
    if args.pergran is None:
        args.pergran = args.permin

    if args.pergran < 1:
        print("Period granularity must be an integer greater than equal to 1", file=sys.stderr)
        return 1

    if (args.permax % args.pergran) != 0:
        print("Period maximum must be a integer multiple of period granularity", file=sys.stderr)
        return 1

    if (args.permin % args.pergran) != 0:
        print("Period minimum must be a integer multiple of period granularity", file=sys.stderr)
        return 1

    args.format = args.format.replace("\\n", "\n")


    gen_tasksets(args)

    return 0


def print_help(parser):
    parser.print_help()

    print("")




if __name__ == "__main__":
	#print(sys.path)
    sys.exit(main())
