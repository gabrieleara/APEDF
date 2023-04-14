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
    parser.add_argument('tsets_in', type=argparse.FileType('r'))
    parser.add_argument('tasks_in', type=argparse.FileType('r'))

    parser.add_argument('-o', "--out-file", default='out.png')
    parser.add_argument('-l', "--log", action='store_true')
    return parser.parse_args()
#-- parse_args

def make_plot(data, outfile, absolute=True):
    if absolute:
        yfield='misses'
        ylabel='Number of Misses'
        ylim=4000
    else:
        yfield='miss_ratio'
        ylabel='Deadline Miss Ratio'
        ylim=1.1

    figure, axis = plt.subplots()
    for number, group in data.groupby('num_tasks'):
        if number > 12:
            continue
        axis.scatter(group['util'], group[yfield], label=f"{number:02d} tasks", alpha=.3)

    axis.set(
        xlabel='Taskset Utilization',
        ylabel=ylabel,
        title='',
    )
    axis.set_ylim(top=ylim)
    axis.grid()
    axis.legend()
    figure.savefig(outfile)

def make_plot_freq(data, outfile):
    figure, axis = plt.subplots()
    for number, group in data.groupby('num_tasks'):
        if number > 12:
            continue
        utils = []
        freqs = []
        for idx, mdata in group.groupby(['util', 'tset_idx']):
                mutil = mdata['util'].min() # There's only one value anyway
                mfreq = mdata['freq'].mean() # This is wrong!!!
                utils.append([mutil])
                freqs.append([mfreq])
        axis.scatter(utils, freqs, label=f"{number:02d} tasks", alpha=.3)
    axis.set(
        xlabel='Taskset Utilization',
        ylabel='Frequency [GHz]',
        title='',
    )
    axis.set_ylim(top=1.5)
    axis.grid()
    axis.legend()
    figure.savefig(outfile)


def main():
    args = parse_args()

    data = pd.read_csv(args.tsets_in, sep='\t', index_col=None)
    data.sort_values(by=['num_tasks', 'util', 'tset_idx'], inplace=True)

    data_tasks = pd.read_csv(args.tasks_in, sep='\t', index_col=None)
    data_tasks.sort_values(by=['num_tasks', 'util', 'tset_idx'], inplace=True)

    make_plot(data, args.out_file + '.abs.png', absolute=True)
    make_plot(data, args.out_file + '.ratio.png', absolute=False)
    make_plot_freq(data_tasks, args.out_file + '.freq.png')

    # data_miss = data[data['miss_ratio'] > 0]
    # data_non_miss = data[data['miss_ratio'] == 0]
    # figure, axis = plt.subplots()
    # axis.scatter(data_non_miss['c_period'] / 1000, data_non_miss['c_duration'] / 1000, s=5, alpha=.25, label='OK', color='cyan')
    # axis.scatter(data_miss['c_period'] / 1000, data_miss['c_duration'] / 1000, s=5, alpha=.25, label='miss', color='red')
    # axis.legend()
    # figure.savefig(args.out_file)

    return 0
#-- main


if __name__ == '__main__':
    sys.exit(main())
