#!/usr/bin/env python3

import chardet
import colored
import enum
import os
import requests
import subprocess
import sys
import time

APEDF_PATH="/root/APEDF"
BOARD_USER="root"
BOARD_IP="10.30.3.51"
RELAY_IP = "10.30.3.203"
RELAY_NAME = "Zarquon"

# ---------------------------------- EPRINT ---------------------------------- #

RESET = colored.attr('reset')

# FIXME: get from environment again
TELEGRAM_CHATID='22176758'
TELEGRAM_BOT_TOKEN='1889907059:AAGn-Wpo0ZDfcDxpuuVch_Iqq41KvAEMYSE'

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
    url = f"http://{RELAY_IP}/settings"
    res = requests.get(url=url)
    if not res.ok:
        return False
    try:
        data = res.json()
        if data['name'] == RELAY_NAME:
            return True
    except:
        pass
    return False


def relay_switch(turn: str = 'NO'):
    url = f"http://{RELAY_IP}/relay/0"
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
    user = BOARD_USER
    host = BOARD_IP
    retcode, outs, errs = sub_cmd("ssh", f"{user}@{host}", "-o", "ConnectTimeout=1", *args)
    return retcode, outs, errs

def parse_progress(outs):
    return outs.strip()

def ping_check():
    retcode, outs, errs = sub_cmd(f"ping -c1 {BOARD_IP}")
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
    if not ping_check():
        return False, None
    progress = None
    errcode, outs, errs = ssh_cmd(f"{APEDF_PATH}/test/test.sh", "check_progress")
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
    errcode, outs, errs = ssh_cmd(f"{APEDF_PATH}/test/test.sh", "start")
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
    if TELEGRAM_CHATID is None or TELEGRAM_BOT_TOKEN is None:
        return

    url = f"https://api.telegram.org/bot{TELEGRAM_BOT_TOKEN}/sendMessage"
    params = {
        # parse_mode : '',
        'chat_id': TELEGRAM_CHATID,
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

def check_and_restart():
    # Possible states:
    # - False, 'RESTART': a reboot occurred, attempt to restart the script
    # - False, None: network connectivity error, try again
    # - False, '???': other error, try again later
    # - True, '[XXX/YYY]': everything ok
    # - True, 'END': experiment is over, get out

    maxcount=0
    time_start=time.time()
    status_ok=False
    while True:
        status_ok, progress = experiment_check_running()
        if status_ok:
            return progress

        if maxcount > 6 or time.time() - time_start > minutes(20):
            raise ExperimentError('Could not restart for a while!!')

        experiment_attempt_start()
        time.sleep(minutes(2))
        maxcount=maxcount+1

def main():
    # TODO: toggle to enable/disable relay stuff
    relay=False

    progress = ''
    time_last_notification=0

    try:
        # Turn on the board
        if relay:
            relay_switch('on')

        while True:
            progress = check_and_restart()

            if progress == 'END':
                break

            if time.time() - time_last_notification > minutes(10):
                notify_progress(progress)
                time_last_notification = time.time()

            time.sleep(minutes(1))

    except (RelayError, ExperimentError) as ex:
        notify_fatal_error(ex)
        return 1

    # Reached when the experiment is over
    notify_finish()
    return 0


if __name__ == "__main__":
    sys.exit(main())
