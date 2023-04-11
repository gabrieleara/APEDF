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
    parser.add_argument('in_file', type=argparse.FileType('r'))

    parser.add_argument('-o', "--out-file", default='out.png')
    parser.add_argument('-l', "--log", action='store_true')
    return parser.parse_args()
#-- parse_args


def main():
    args = parse_args()

    data = pd.read_csv(args.in_file, sep='\t', index_col=None)

    # data_miss = data[data['miss_ratio'] > 0]
    # data_non_miss = data[data['miss_ratio'] == 0]

    # figure, axis = plt.subplots()
    # axis.scatter(data_non_miss['c_period'] / 1000, data_non_miss['c_duration'] / 1000, s=5, alpha=.25, label='OK', color='cyan')
    # axis.scatter(data_miss['c_period'] / 1000, data_miss['c_duration'] / 1000, s=5, alpha=.25, label='miss', color='red')
    # axis.legend()
    # figure.savefig(args.out_file)
    # return 0

    data.sort_values(by=['num_tasks', 'util', 'tset_idx'], inplace=True)

    figure, axis = plt.subplots()

    for number, group in data.groupby('num_tasks'):
        # if number == 16:
        #     continue
        axis.scatter(group['util'], group['miss_ratio'], label=f"{number:02d} tasks", alpha=.3)

    # # data.groupby('num_tasks').plot(x='util', y='miss_ratio', kind='scatter', legend=True, ax=axis)
    # data.plot(x='util', y='miss_ratio', kind='scatter', legend=True, ax=axis) #, index=['num_tasks'])

    axis.set(
        xlabel='Taskset Utilization',
        ylabel='Deadline Miss Ratio',
        title='',
    )
    axis.grid()
    axis.legend()

    if args.log:
        plt.yscale('log')

    figure.savefig(args.out_file)
    # plt.show()

    return 0
#-- main


if __name__ == '__main__':
    sys.exit(main())
