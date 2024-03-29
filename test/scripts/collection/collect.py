#!/usr/bin/env python3

import argparse
import os
import parse
import sys

import pandas as pd
import numpy as np


def eprint(*args, **kwargs):
    print(*args, file=sys.stderr, **kwargs)


def arguments_parser():
    parser = argparse.ArgumentParser()
    parser.add_argument("in_dir", type=str)
    parser.add_argument('-o', "--out-file",
                        default='/dev/stdout',
                        help="Where to save stats for each taskset",
                        )
    parser.add_argument('-O', "--out-file2",
                        default='/dev/null',
                        help="Where to save stats for each task in each taskset",
                        )
    parser.add_argument('-m', "--print-misses",
                        action='store_true',
                        help="Log on STDERR each deadline miss",
                        )
    parser.add_argument('-d', "--discard-small",
                        action='store_true',
                        help="Discard tasksets with very small tasks",
                        )
    parser.add_argument('-D', "--discard-overrun",
                        action='store_true',
                        help="Discard tasksets for which there is at least one overrun (exec time greather than dl_runtime)",
                        )
    return parser


DISCARD_SMALL = False
DISCARD_OVERRUN = False
PRINT_MISSES = False


class TooShort(Exception):
    pass


class AllTasksSkipped(Exception):
    pass


class Overrun(Exception):
    pass


class ThermalThrottling(Exception):
    pass


class EmptyExperiment(Exception):
    pass


def parse_task(task_logfile):
    # Logfiles have multiple spaces as a single separator
    task_log = pd.read_csv(task_logfile, delimiter=r"\s+")
    task_log.rename(columns={'#idx': 'idx'}, inplace=True)

    # Normalizing some data (see below)
    task_log['dl_period'] //= 1000
    task_log['dl_runtime'] //= 1000
    task_log['dl_deadline'] //= 1000
    task_log['freq'] /= 1000000.0

    # Fields description:
    # - idx:        STATIC          task index in taskset
    # - perf:       STATIC          fixed amount of work performed (c_duration / calibration)
    # - run:        DYNAMIC [us]    time spent to execute
    # - period:     DYNAMIC [us]    time spent including sleep and slack
    # - start:      DYNAMIC [us]    absolute start time
    # - end:        DYNAMIC [us]    absolute end time
    # - rel_st      DYNAMIC [us]    start time of a phase relatively to the beg of the use case
    # - slack       DYNAMIC [us]    remaining time before the task deadline
    # - c_duration  STATIC  [us]    expected execution time
    # - c_period    STATIC  [us]    expected activation period
    # - wu_lat      DYNAMIC [us]    sum of wakeup latencies after timer events
    # - cpu         DYNAMIC         CPU id where it executed
    # - freq        DYNAMIC [GHz]   CPU frequency
    # - dl_runtime  STATIC  [us]    SCHED_DEADLINE parameter
    # - dl_period   STATIC  [us]    SCHED_DEADLINE parameter
    # - dl_deadline STATIC  [us]    SCHED_DEADLINE parameter

    # Drop first 10 seconds
    # exp_start_time = task_log['start'][0]
    # task_log = task_log[task_log['start'] > exp_start_time + 10 * 1000000]
    # task_log = task_log.reset_index()

    # Drop after the first 50 seconds
    exp_start_time = task_log['start'][0]
    task_log = task_log[task_log['end'] <= exp_start_time + 59 * 1000000]
    task_log = task_log.reset_index()

    if task_log.empty:
        print("ERROR:", task_logfile)
        raise EmptyExperiment

    # Collapse all static fields in a more accessible struct
    STATIC_FIELDS = [
        'idx',
        'perf',
        'c_duration',
        'c_period',
        'dl_runtime',
        'dl_period',
        'dl_deadline',
        # Assuming that there are zero migrations:
        'cpu',
        # Not really but sure
        # 'freq',
    ]
    task_info = {
        'filename': task_logfile,
    }
    for field in STATIC_FIELDS:
        # print(field)
        # print(task_log)
        task_info[field] = task_log[field][0]

    # For now we skip all tasks with not enough runtime
    if task_info['c_duration'] < 5000 and DISCARD_SMALL:
        raise TooShort

    # Extra fields:
    # - exec_ratio: ratio between the expected runtime (reservation) and the
    #               actual one (if >= 1 we had an overrun!)
    task_log['exec_ratio_to_expected'] = task_log['run'] / \
        task_log['c_duration']
    task_log['exec_ratio_to_reservation'] = task_log['run'] / \
        (task_log['dl_runtime'])

    # Count all rows
    count = task_log['slack'].count()

    # Approximate experiment duration
    tot_duration = task_log['end'].max() - task_log['start'].min()

    # # Count the number of overruns, if positive of course we have misses!
    # num_overruns = task_log['exec_ratio_to_reservation'].ge(1).sum()
    # if num_overruns > 5 and DISCARD_OVERRUN:
    #     eprint(
    #         f"{num_overruns} / {count} !!")
    #     raise Overrun

    # if len(task_log['freq'].unique()) != 1 or task_log['freq'][0] != 1400:
    #     raise ThermalThrottling

    # If we get here, everything should be alright (exception thrown by other
    # tasks must be taken into account in the taskset parser function, so that
    # we skip those tasks)

    # Count all rows with a negative slack and calculate miss ratio
    misses = task_log[task_log['slack'] < 0]['slack'].count()
    miss_ratio = misses / count
    minslack = task_log['slack'].min()
    maxslack = task_log['slack'].max()

    if misses > 0 and PRINT_MISSES:
        eprint(f"Task {task_logfile} has {misses} misses!")

    # Count migrations
    def mark_migrations(col):
        x = (col != col.shift().bfill())
        s = x.cumsum()
        return s.groupby(s).transform('count').shift().where(x)

    # NOTE: I want a DF with a single column, not a Series
    task_placement = task_log[['cpu']]
    task_placement = task_placement.apply(mark_migrations)
    migrations = task_placement['cpu'].count()
    migrations_ratio = migrations / count

    # Frequency accounting
    freq_timeseries = task_log[['start', 'freq']][1:]

    return {
        **task_info,
        'count':        count,
        'misses':       misses,
        'miss_ratio':   miss_ratio,
        'minslack':     minslack,
        'maxslack':     maxslack,
        'migrations':   migrations,
        'migrations_ratio': migrations_ratio,
        'tot_duration': tot_duration,
        'freq': freq_timeseries # NOTE: THIS IS AN ARRAY of pairs!!!
    }

def weighted_percentile(data, weights, perc):
    """
    perc : percentile in [0-1]!
    """
    ix = np.argsort(data)
    data = data[ix] # sort data
    weights = weights[ix] # sort weights
    cdf = (np.cumsum(weights) - 0.5 * weights) / np.sum(weights) # 'like' a CDF function
    return np.interp(perc, cdf, data)

def parse_taskset(tset_dir):
    global tsets_type

    tset_dirname = os.path.basename(tset_dir)
    tset_info = parse.parse("ts_n{num_tasks:2d}_i{tset_idx:2d}_u{util:f}.out.d",
                            tset_dirname)
    mperiod_info = parse.parse("{period:d}.out.d", tset_dirname)

    if tset_info is None and mperiod_info is None:
        eprint(
            f"Error: invalid directory specified, could not parse taskset data from directory {tset_dir}")
        sys.exit(1)

    # Special for dhall-effect tasks
    if tset_info is None:
        tset_info = mperiod_info
        if tsets_type is not None and tsets_type != 'dhall':
            eprint(f"Multiple taskset types (both {tsets_type} and dhall)")
            sys.exit(1)
        tsets_type = 'dhall'
    else:
        if tsets_type is not None and tsets_type != 'regular':
            eprint(f"Multiple taskset types (both {tsets_type} and regular)")
            sys.exit(1)
        tsets_type = 'regular'

    # Get dictionary from parse result type
    tset_info = tset_info.named

    therm_data = pd.read_csv(f"{tset_dir}/therm.log", sep=' ', header=None)

    # The fifth column should refer to the GPU, we will discard it for now
    # Get the maximum among the maximum values of each of the first 4 columns
    therm_max = therm_data.iloc[:, :4].max().max()


    # TODO
    # power_data = pd.read_csv(f"{tset_dir}/therm.log", sep=',')

    tset_stats = {
        **tset_info,
        'count': 0,
        'misses': 0,
        'miss_ratio': 0,
        'minslack': float('inf'),
        'maxslack': -float('inf'),
        'migrations': 0,
        'migrations_ratio': 0,
        'therm_max': therm_max,
    }

    tasks_stats = []
    freq_timeseries = []

    task_dirs = [d for d in os.listdir(tset_dir) if 'rt-app-task' in d]
    for tdir in task_dirs:
        # This function may raise an exception, which will make us skip this taskset

        # FIX: for now, tasks that run for more than their budget will NOT be
        # counted, but will not disqualify the taskset entirely
        try:
            tstats = parse_task(os.path.join(tset_dir, tdir))
        except (TooShort, Overrun) as error:
            eprint(
                f"WARN: {type(error).__name__}, skipping {os.path.join(tset_dir, tdir)} ...")
            continue

        # List of timeseries
        freq_timeseries.append(tstats['freq'])
        tstats.pop('freq')

        tstats = {
            **tset_info,
            **tstats,
        }

        tasks_stats += [tstats]

        tset_stats['count'] += tstats['count']
        tset_stats['misses'] += tstats['misses']
        tset_stats['migrations'] += tstats['migrations']
        tset_stats['minslack'] = min(
            tstats['minslack'], tset_stats['minslack'])
        tset_stats['maxslack'] = max(
            tstats['maxslack'], tset_stats['maxslack'])
        # tset_stats['freq_mean'] = freqs

    try:
        tset_stats['miss_ratio'] = tset_stats['misses'] / tset_stats['count']
        tset_stats['migrations_ratio'] = tset_stats['migrations'] / tset_stats['count']
    except ZeroDivisionError:
        raise AllTasksSkipped

    freq_timeseries = pd.concat(freq_timeseries, ignore_index=True)
    freq_timeseries.sort_values(by=['start'], inplace=True)
    freq_timeseries = freq_timeseries.reset_index(drop=True)

    freqs = []
    weights = []

    t_prev = freq_timeseries['start'][0]
    f_prev = freq_timeseries['freq'][0]
    for index, row in freq_timeseries[1:].iterrows():
        freqs += [f_prev]
        t_next = row['start']
        weights += [t_next - t_prev]
        t_prev = t_next
        f_prev = row['freq']

    tot_weights = sum(weights)

    the_freqs = [.2, .3, .4, .5, .6, .7, .8, .9, 1.0, 1.1, 1.2, 1.3, 1.4]
    the_weights = [0,0,0,0,0,0,0,0,0,0,0,0,0]

    for idx in range(len(the_freqs)):
        for f, w in zip(freqs, weights):
            if f == the_freqs[idx]:
                the_weights[idx] += w

    for i in range(len(the_freqs)):
        if the_weights[i] > 0:
            freq_min = the_freqs[i]
            break

    for i in reversed(range(len(the_freqs))):
        if the_weights[i] > 0:
            freq_max = the_freqs[i]
            break

    the_freqs = np.asarray(the_freqs)
    the_weights = np.asarray(the_weights)

    freq_q20 = weighted_percentile(the_freqs, the_weights, .20)
    freq_q50 = weighted_percentile(the_freqs, the_weights, .50)
    freq_mean = np.average(the_freqs, weights=the_weights)

    tset_stats['freq_min'] = freq_min
    tset_stats['freq_q20'] = freq_q20
    tset_stats['freq_q50'] = freq_q50
    tset_stats['freq_mean'] = freq_mean
    tset_stats['freq_max'] = freq_max

    # 1. The stats of the whole taskset
    # 2. List of the stats of each task
    return tset_stats, tasks_stats

tsets_type = None

def main():
    global PRINT_MISSES
    global DISCARD_OVERRUN
    global DISCARD_SMALL

    parser = arguments_parser()
    args = parser.parse_args()

    PRINT_MISSES = args.print_misses
    DISCARD_OVERRUN = args.discard_overrun
    DISCARD_SMALL = args.discard_small

    tasks_rows = []
    tsets_rows = []

    if not os.path.isdir(args.in_dir):
        eprint(
            f"Supplied directory argument {args.in_dir} is not a valid directory!")
        parser.print_help()
        return 1

    tset_dirs = [d for d in os.listdir(args.in_dir) if 'out.d' in d]
    for tset_dir in tset_dirs:
        try:
            tset_stats, tasks_stats = parse_taskset(
                os.path.join(args.in_dir, tset_dir))
        except (TooShort, Overrun, AllTasksSkipped, ThermalThrottling) as error:
            eprint(
                f"WARN: {type(error).__name__}, skipping {tset_dir} ...")
            continue

        tsets_rows += [tset_stats]
        tasks_rows += tasks_stats

    if len(tsets_rows) < 1 or len(tasks_rows) < 1:
        eprint('ERROR: No tasks or tasksets!! Everything was discarded!')
        return 1

    tasks_stats = pd.DataFrame(tasks_rows)
    tsets_stats = pd.DataFrame(tsets_rows)

    global tsets_type
    if tsets_type == 'dhall':
        tsets_cols_order = ['period']
    else:
        tsets_cols_order = ['num_tasks', 'util', 'tset_idx',]

    tasks_cols_order = tsets_cols_order + ['idx']

    # Sort the rows in ascending order according to these columns
    tsets_stats = tsets_stats.sort_values(tsets_cols_order, ignore_index=True)
    tasks_stats = tasks_stats.sort_values(tasks_cols_order, ignore_index=True)

    # Sort the columns as well
    tsets_stats = tsets_stats.reindex(columns=(
        tsets_cols_order + list([c for c in tsets_stats.columns if c not in tsets_cols_order])))
    tasks_stats = tasks_stats.reindex(columns=(
        tasks_cols_order + list([c for c in tasks_stats.columns if c not in tasks_cols_order])))

#     # To debug the dataframes
#     print(f"""
# ---- TASKSETS INFO ----
# {tsets_stats}
#
# ---- TASKS INFO ----
# {tasks_stats}
# """)

    tsets_out_file = args.out_file
    tasks_out_file = args.out_file2

    if tsets_out_file != '/dev/null':
        print('Printing TASKSETS info')
        if tsets_out_file == '/dev/stdout':
            print('-------------------------')
        tsets_stats.to_csv(
            tsets_out_file,
            sep='\t',
            index=False,
        )
        if tsets_out_file == '/dev/stdout':
            print('-------------------------')

    if tasks_out_file != '/dev/null':
        print('Printing TASKS info')
        if tasks_out_file == '/dev/stdout':
            print('-------------------------')
        tasks_stats.to_csv(
            tasks_out_file,
            sep='\t',
            index=False,
        )
        if tasks_out_file == '/dev/stdout':
            print('-------------------------')

    return 0


if __name__ == "__main__":
    sys.exit(main())
