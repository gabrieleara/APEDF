#!/usr/bin/env python3

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
    parser.add_argument("in_dir", type=dir_path)
    parser.add_argument('-o', "--out-file", default='/dev/stdout')
    parser.add_argument('-m', "--print-misses", action='store_true')
    return parser.parse_args()
#-- parse_args


def main():
    args = parse_args()

    tset_dirs = [d for d in os.listdir(args.in_dir) if 'rt-app.d' in d]

    rows = {}

    df = pd.DataFrame()

    for d in tset_dirs:
        tset_dir = args.in_dir + "/" + d

        splits = d.split('_n')

        splits = splits[1].split('_i')
        ts_ntasks = splits[0]

        splits = splits[1].split('_u')
        ts_idx = splits[0]

        splits = splits[1].split('.')
        ts_util = float(splits[0] + '.' + splits[1])

        n_u = {
            'ntasks': ts_ntasks,
            'util': ts_util,
        }

        key = frozenset(n_u.items())

        if key not in rows:
            rows[key] = {
                'count': 0,
                'misses': 0,
                'miss-ratio': 0,
                'minslack': float('inf'),
            }
        # --

        task_dirs = [d for d in os.listdir(tset_dir) if 'rt-app-task' in d]

        for t in task_dirs:
            task_log = tset_dir + '/' + t
            # task_idx = t.split('-')[3].split('.')[0]

            logs = pd.read_csv(task_log, delimiter=r"\s+")

            rows[key]['count'] += logs['slack'].count()

            thesemisses = logs['slack'].lt(0).sum()

            rows[key]['misses'] += thesemisses

            if thesemisses > 0 and args.print_misses:
                eprint(task_log)

            rows[key]['miss-ratio'] = \
                rows[key]['misses'] / rows[key]['count']

            m = logs['slack'].min()
            rows[key]['minslack'] = \
                m if m < rows[key]['minslack'] \
                else rows[key]['minslack']
        # --
    # --

    for key in rows:
        n_u = dict(key)
        data = {
            'ntasks': n_u['ntasks'],
            'util': n_u['util'],
            **rows[key]
        }
        df = df.append(data, ignore_index=True)

    df = df.sort_values(by=['ntasks', 'util'])
    df.to_csv(
        args.out_file,
        sep='\t',
        index=False,
    )
    return 0
#-- main


if __name__ == "__main__":
    main()
