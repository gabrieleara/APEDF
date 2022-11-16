#!/usr/bin/env python3

import matplotlib.pyplot as plt
import pandas as pd
import argparse
import os

import sys


def eprint(*args, **kwargs):
    print(*args, file=sys.stderr, **kwargs)


def dir_path(string):
    if os.path.isdir(string):
        return string
    else:
        raise NotADirectoryError(string)
#-- dir_path


def parse_args():
    parser = argparse.ArgumentParser()
    parser.add_argument('in_files', type=argparse.FileType('r'), nargs='+')

    # parser.add_argument("in_dir", type=dir_path)
    parser.add_argument('-o', "--out-file", default='out.png')
    parser.add_argument('-l', "--log", action='store_true')
    return parser.parse_args()
#-- parse_args


def main():
    args = parse_args()

    dfs = {}

    for f in args.in_files:
        filename = f.name
        label = os.path.splitext(os.path.basename(filename))[0]
        dfs[label] = pd.read_csv(f, sep='\t', index_col=None, header=0)

    fig, ax = plt.subplots()

    for label in dfs:
        ax.plot(
            dfs[label]['util'],
            dfs[label]['miss-ratio'],
            label=label,
        )

    ax.set(
        xlabel='Taskset Utilization',
        ylabel='Deadline Miss Ratio',
        title='',
    )
    ax.grid()
    ax.legend()

    if args.log:
        plt.yscale('log')

    fig.savefig(args.out_file)
    plt.show()

    return 0
#-- main


if __name__ == '__main__':
    main()
