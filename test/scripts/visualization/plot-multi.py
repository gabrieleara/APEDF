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


def transparent_print(outfile):
    return True if '.svg' in str(outfile) else False


def parse_args():
    parser = argparse.ArgumentParser()
    parser.add_argument('tasks_apedfff', type=argparse.FileType('r'))
    parser.add_argument('tasks_apedfwf', type=argparse.FileType('r'))
    parser.add_argument('tasks_global', type=argparse.FileType('r'))

    parser.add_argument('tsets_apedfff', type=argparse.FileType('r'))
    parser.add_argument('tsets_apedfwf', type=argparse.FileType('r'))
    parser.add_argument('tsets_global', type=argparse.FileType('r'))

    parser.add_argument('-o', "--out-file-base", default='out')
    parser.add_argument('-O', "--out-file-format", default='png')
    return parser.parse_args()
#-- parse_args

def plot_data_freq(axis, data, label, which='mean'):
    utils = []
    freqs = []
    for util, group in data.groupby('util'):
        # All taskset durations are the same, so pick always the mean (whatever)
        mfreq = group['freq_' + which].mean()
        utils.append([util])
        freqs.append([mfreq])
    axis.plot(utils, freqs, label=label)

def plot_data_miss(axis, data, label, which='mean', quantile=.5):
    utils = []
    miss_ratios = []
    for util, group in data.groupby('util'):
        if which == 'quantile':
                mmiss_ratio = group['miss_ratio'].quantile(q=quantile)
        else:
                mmiss_ratio = getattr(group['miss_ratio'], which)()
        utils.append([util])
        miss_ratios.append([mmiss_ratio])
    axis.plot(utils, miss_ratios, label=label)

def make_plot_freq(data_dict, outfile, which='mean'):
    figure, axis = plt.subplots()

    for key, data in data_dict.items():
        plot_data_freq(axis, data, key, which=which)
    axis.set(
        xlabel='Taskset Utilization',
        ylabel='Frequency [GHz]',
        title='',
    )
    # bottom=1.0 if performance else 0
    axis.set_ylim(top=1.5, bottom=0)
    axis.grid()
    axis.legend()
    figure.savefig(outfile, transparent=transparent_print(outfile))

def make_plot_miss(data_dict, outfile, which='mean', quantile=.5, log=False):
    figure, axis = plt.subplots()

    for key, data in data_dict.items():
        plot_data_miss(axis, data, key, which=which, quantile=quantile)
    axis.set(
        xlabel='Taskset Utilization',
        ylabel='Miss Ratio',
        title='',
    )
    if log:
        axis.set_yscale('log')
    # bottom=1.0 if performance else 0
    axis.set_ylim(top=.7, bottom=-0.1)
    axis.grid()
    axis.legend()
    figure.savefig(outfile, transparent=transparent_print(outfile))


def read_data(infile):
    data = pd.read_csv(infile, sep='\t', index_col=None)
    data.sort_values(by=['util'], inplace=True)
    return data

def main():
    args = parse_args()

    data_apedfff = read_data(args.tasks_apedfff)
    data_apedfwf = read_data(args.tasks_apedfwf)
    data_global  = read_data(args.tasks_global)

    data_tsets_apedfff = read_data(args.tsets_apedfff)
    data_tsets_apedfwf = read_data(args.tsets_apedfwf)
    data_tsets_global  = read_data(args.tsets_global)

    data_dict = {
        ' G-EDF': data_global,
        'AP-EDF FF': data_apedfff,
        'AP-EDF WF': data_apedfwf,
    }

    data_dict_tsets = {
        ' G-EDF':    data_tsets_global,
        'AP-EDF FF': data_tsets_apedfff,
        'AP-EDF WF': data_tsets_apedfwf,
    }

    make_plot_freq(data_dict_tsets, f"{args.out_file_base}.freq-lines.mean.{args.out_file_format}", which='mean')
    make_plot_freq(data_dict_tsets, f"{args.out_file_base}.freq-lines.min.{args.out_file_format}", which='min')
    make_plot_freq(data_dict_tsets, f"{args.out_file_base}.freq-lines.max.{args.out_file_format}", which='max')
    make_plot_freq(data_dict_tsets, f"{args.out_file_base}.freq-lines.q20.{args.out_file_format}", which='q20')
    make_plot_freq(data_dict_tsets, f"{args.out_file_base}.freq-lines.q50.{args.out_file_format}", which='q50')

    make_plot_miss(data_dict, f"{args.out_file_base}.miss-lines.mean.{args.out_file_format}", which='mean')
    make_plot_miss(data_dict, f"{args.out_file_base}.miss-lines-log.mean.{args.out_file_format}", which='mean', log=True)
    make_plot_miss(data_dict, f"{args.out_file_base}.miss-lines.min.{args.out_file_format}", which='min')
    make_plot_miss(data_dict, f"{args.out_file_base}.miss-lines.max.{args.out_file_format}", which='max')
    make_plot_miss(data_dict, f"{args.out_file_base}.miss-lines.q20.{args.out_file_format}", which='quantile', quantile=.20)
    make_plot_miss(data_dict, f"{args.out_file_base}.miss-lines.q50.{args.out_file_format}", which='quantile', quantile=.50)
    make_plot_miss(data_dict, f"{args.out_file_base}.miss-lines.q90.{args.out_file_format}", which='quantile', quantile=.90)

    return 0
#-- main


if __name__ == '__main__':
    sys.exit(main())
