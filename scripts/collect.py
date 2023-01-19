#!/usr/bin/env python3

import argparse
import os
import pandas as pd
import parse
import sys


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
                        help="Discard tasksets for which there is at least one overrun (exec time greather than c_runtime)",
                        )
    return parser


DISCARD_SMALL = False
DISCARD_OVERRUN = False
PRINT_MISSES = False


class TooShortException(Exception):
    pass


class AllTasksSkippedException(Exception):
    pass


class OverrunException(Exception):
    pass


def parse_task(task_logfile):
    # Logfiles have multiple spaces as a single separator
    task_log = pd.read_csv(task_logfile, delimiter=r"\s+")
    task_log.rename(columns={'#idx': 'idx'}, inplace=True)

    # Fields description:
    # - idx:        STATIC          task index in taskset
    # - perf:       STATIC          fixed amount of work performed (c_duration / calibration)
    # - run:        DYNAMIC [us]    time spent to execute
    # - period:     DYNAMIC [us]    time spent including sleep and slack
    # - start:      DYNAMIC [us]    absolute start time
    # - end:        DYNAMIC [us]    absolute end time
    # - rel_st      DYNAMIC [us]    start time of a phase relatively to the beg of the use case
    # - slack       DYNAMIC [us]    remaining time before the task deadline
    # - c_duration  STATIC  [us]    expected execution time         [SCHED_DEADLINE parameter]
    # - c_period    STATIC  [us]    expected activation period          [SCHED_DEADLINE parameter]
    # - wu_lat      DYNAMIC [us]    sum of wakeup latencies after timer events
    # - cpu         DYNAMIC         CPU id where it executed

    # Collapse all static fields in a more accessible struct
    STATIC_FIELDS = ['idx', 'perf', 'c_duration', 'c_period', ]
    task_info = {}
    for field in STATIC_FIELDS:
        task_info[field] = task_log[field][0]

    # For now we skip all tasks with not enough runtime
    if task_info['c_duration'] < 5000 and DISCARD_SMALL:
        raise TooShortException

    # Extra fields:
    # - exec_ratio: ratio between the expected runtime (reservation) and the
    #               actual one (if >= 1 we had an overrun!)
    task_log['exec_ratio'] = task_log['run'] / task_log['c_duration']

    # Count the number of overruns, if positive of course we have misses!
    if task_log['exec_ratio'].ge(1).count() > 0 and DISCARD_OVERRUN:
        eprint(
            f"{task_log['exec_ratio'].ge(1).count()} / {task_log['slack'].count()} !!")
        raise OverrunException

    # If we get here, everything should be alright (exception thrown by other
    # tasks must be taken into account in the taskset parser function, so that
    # we skip those tasks)

    # Count all rows and all the ones with a negative slack
    count = task_log['slack'].count()
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

    return {
        **task_info,
        'count':        count,
        'misses':       misses,
        'miss_ratio':   miss_ratio,
        'minslack':     minslack,
        'maxslack':     maxslack,
        'migrations':   migrations,
    }


def parse_taskset(tset_dir):
    tset_dirname = os.path.basename(tset_dir)
    tset_info = parse.parse("ts_n{num_tasks:2d}_i{tset_idx:2d}_u{util:f}.rt-app.d",
                            tset_dirname)

    if tset_info is None:
        eprint(
            f"Error: invalid directory specified, could not parse taskset data from directory {tset_dir}")
        sys.exit(1)

    # Get dictionary from parse result type
    tset_info = tset_info.named

    tset_stats = {
        **tset_info,
        'count': 0,
        'misses': 0,
        'miss_ratio': 0,
        'minslack': float('inf'),
        'maxslack': -float('inf'),
        'migrations':   0,
    }

    tasks_stats = []

    task_dirs = [d for d in os.listdir(tset_dir) if 'rt-app-task' in d]
    for tdir in task_dirs:
        # This function may raise an exception, which will make us skip this taskset

        # FIX: for now, tasks that run for more than their budget will NOT be
        # counted, but will not disqualify the taskset entirely
        try:
            tstats = parse_task(os.path.join(tset_dir, tdir))
        except (TooShortException, OverrunException) as error:
            eprint(
                f"WARN: {type(error).__name__}, skipping {os.path.join(tset_dir, tdir)} ...")
            continue

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

    try:
        tset_stats['miss_ratio'] = tset_stats['misses'] / tset_stats['count']
    except ZeroDivisionError:
        raise AllTasksSkippedException

    # 1. The stats of the whole taskset
    # 2. List of the stats of each task
    return tset_stats, tasks_stats


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

    tset_dirs = [d for d in os.listdir(args.in_dir) if 'rt-app.d' in d]
    for tset_dir in tset_dirs:
        try:
            tset_stats, tasks_stats = parse_taskset(
                os.path.join(args.in_dir, tset_dir))
        except (TooShortException, OverrunException, AllTasksSkippedException) as error:
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

    tsets_cols_order = ['num_tasks', 'util', 'tset_idx']
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
