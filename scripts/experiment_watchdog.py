#!/usr/bin/env python3

import chardet
import colored
import enum
import os
import requests
import subprocess
import sys
import time

# ---------------------------------- EPRINT ---------------------------------- #

RESET = colored.attr('reset')


class MsgClass(enum.Enum):
    PLAIN = enum.auto()
    OK = enum.auto()
    ERROR = enum.auto()


COLOR_MAP = {
    MsgClass.PLAIN: colored.fg("white"),
    MsgClass.OK: colored.fg("green"),
    MsgClass.ERROR: colored.fg("red")
}


class eprint:
    def __init__(self, *args, **kwargs):
        eprint.raw(MsgClass.PLAIN, *args, **kwargs)

    @staticmethod
    def raw(msg_class: MsgClass, *args, **kwargs):
        color = COLOR_MAP[msg_class]
        print(color, *args, RESET, **kwargs)

    @staticmethod
    def plain(*args, **kwargs):
        eprint.raw(MsgClass.PLAIN, *args, **kwargs)

    @staticmethod
    def ok(*args, **kwargs):
        eprint.raw(MsgClass.OK, *args, **kwargs)

    @staticmethod
    def error(*args, **kwargs):
        eprint.raw(MsgClass.ERROR, *args, **kwargs)


# -------------------------------- EXCEPTIONS -------------------------------- #

class RelayError(Exception):
    pass


class ExperimentError(Exception):
    pass

# --------------------------- TIME MANAGEMENT CODE --------------------------- #


def seconds(s):
    return s


def minutes(m):
    return seconds(m) * 60


def hours(h):
    return minutes(h) * 60


def to_minutes(s):
    return s / 60


def to_hours(s):
    return to_minutes(s) / 60


# -------------------------- RELAY MANAGEMENT CODE --------------------------- #


def relay_check_name():
    url = "http://10.30.3.203/settings"
    res = requests.get(url=url)
    if not res.ok:
        return False
    try:
        data = res.json()
        if data['name'] == 'Zarquon':
            return True
    except:
        pass
    return False


def relay_switch(turn: str = 'NO'):
    url = "http://10.30.3.203/relay/0"
    params = {}

    if turn != 'NO':
        params['turn'] = turn

    res = requests.get(url=url, params=params)
    if not res.ok:
        return False
    try:
        data = res.json()
        return data['ison']
    except:
        pass
    return False


def relay_reboot():
    if not relay_check_name():
        raise RelayError("Name does not match!")
    if relay_switch('off'):
        raise RelayError("Did not turn off!")
    time.sleep(seconds(10))
    if not relay_switch('on'):
        raise RelayError("Did not turn on!")


# ------------------------ EXPERIMENT MANAGEMENT CODE ------------------------ #

# TODO: how to check for the end of the experiment

def decode_detect(bstr):
    detected = chardet.detect(bstr)
    if detected['encoding'] is None:
        return bstr
    return bstr.decode(detected['encoding'], 'ignore')

def sub_cmd(*args):
    cmd = ' '.join([*args])

    child_process = subprocess.Popen(
        cmd,
        shell=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )

    # Wait for termination
    try:
        outs, errs = child_process.communicate(timeout=15)
    except subprocess.TimeoutExpired:
        child_process.kill()
        outs, errs = child_process.communicate()

    # Decode output from detected encoding (ascii or utf-8, or whatever)
    outs = decode_detect(outs)
    errs = decode_detect(errs)

    return child_process.returncode, outs, errs

def ssh_cmd(*args):
    user = 'root'
    host = 'zarquon'
    retcode, outs, errs = sub_cmd("ssh", f"{user}@{host}", "-o", "ConnectTimeout=1", *args)
    return retcode, outs, errs

def parse_progress(outs):
    return outs.strip()

def ping_check():
    retcode, outs, errs = sub_cmd("ping -c1 10.30.3.51")
    if retcode != 0:
        msg = f'Could not ping! {errs}'.strip()
        eprint.error("FAILURE!")
        eprint.error(msg)
        notify_send(msg)
        return False
    else:
        eprint.ok("Ping successful...", end=' ')
    return True


def experiment_check_running():
    eprint.plain(f'Check in progress...', end=' ')
    progress = None
    if not ping_check():
        return False, progress
    errcode, outs, errs = ssh_cmd("/root/APEDF/scripts/check_progress.sh")
    if errcode != 0:
        eprint.error("FAILURE!")
        eprint.error(errs)
        return False, progress

    # Parse progress from STDOUT
    progress = parse_progress(outs)
    eprint.ok(f'SUCCESSFUL!')
    return True, progress


def experiment_attempt_start():
    eprint.plain(f"Attempting to start experiment...", end=" ")
    errcode, outs, errs = ssh_cmd("/root/APEDF/scripts/start_experiment.sh")
    if errcode != 0:
        eprint.error("FAILURE!")
        eprint.error(errs)
        return False
    eprint.ok("STARTED!")
    return True


def experiment_start():
    time_begin = time.time()
    success = False
    while (not success) and (time.time() - time_begin < minutes(10)):
        if experiment_attempt_start():
            return
        time.sleep(seconds(30))
    raise ExperimentError("Could not start experiment for 10 minutes!")


# ---------------------------- NOTIFICATION CODE ----------------------------- #

def notify_send(msg):
    CHATID = os.getenv('TELEGRAM_ARARAUNA_CHATID')
    TOKEN = os.getenv('TELEGRAM_ARARAUNA_NOTIFIER_BOT_TOKEN')

    if CHATID is None or TOKEN is None:
        return

    url = f"https://api.telegram.org/bot{TOKEN}/sendMessage"
    params = {
        # parse_mode : '',
        'chat_id': CHATID,
        'text': msg,
    }

    # Ignore response or error
    requests.get(url=url, params=params)


def notify_finish():
    msg = "Experiments finished!!"
    eprint.ok(msg)
    notify_send(msg)
    return


def notify_progress(progress):
    msg = f'Current experiment progress {progress}'
    eprint.plain(msg)
    notify_send(msg)
    return


def notify_experiment_error():
    msg = 'More than 20 minutes without a response!'
    eprint.error(msg, file=sys.stderr)
    notify_send(msg)
    pass


def notify_fatal_error(ex):
    msg = f'{type(ex).__name__}: {ex}'
    eprint.error(msg, file=sys.stderr)
    notify_send(msg)
    pass


# ------------------------------ WATCHDOG CODE ------------------------------- #

def main():
    try:
        # Turn on the board
        relay_switch('on')

        # Start the experiment
        experiment_start()

        time.sleep(seconds(20))
        started, progress = experiment_check_running()

        if not started:
            raise ExperimentError('Could not start experiment for the first time!')

        if progress == 'END':
            # Do nothing and exit
            finished = True
        else:
            # At the beginning wait for a little longer, it will likely not break
            # right after being started!
            finished = False
            time.sleep(minutes(20))
            time_last_successful_check = time.time()

        # Forever
        while not finished:
            status, progress = experiment_check_running()
            if status:
                if progress == 'END':
                    finished = True
                    continue

                # On success try again in 10 minutes
                notify_progress(progress)
                time.sleep(minutes(10))
                time_last_successful_check = time.time()
                continue

            # On failure, do not panic yet! Try again, but progressively sooner
            elapsed = time.time() - time_last_successful_check
            eprint.plain(
                f'Minutes since last successful check: {to_minutes(elapsed)}')
            if elapsed < minutes(5):
                time.sleep(minutes(4))
                continue

            if elapsed < minutes(7):
                time.sleep(minutes(1))
                continue

            if elapsed < minutes(10):
                time.sleep(seconds(30))
                continue

            notify_experiment_error()

            # Twenty minutes without a successful check, time to halt everything
            # and reboot! Then sleep for a while, it will likely not break soon.
            relay_reboot()
            experiment_start()
            time.sleep(minutes(20))
            time_last_successful_check = time.time()

    except (RelayError, ExperimentError) as ex:
        notify_fatal_error(ex)
        return 1

    # Reached when the experiment is over
    notify_finish()
    return 0


if __name__ == "__main__":
    sys.exit(main())
