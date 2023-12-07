#!/usr/bin/env python3

import os
import sys
import requests

def eprint(*args, **kwargs):
    print(*args, file=sys.stderr, **kwargs)


def notify_send(msg):
    TELEGRAM_CHATID = os.getenv('TELEGRAM_CHATID')
    TELEGRAM_BOT_TOKEN = os.getenv('TELEGRAM_BOT_TOKEN')

    if TELEGRAM_CHATID is None or TELEGRAM_BOT_TOKEN is None:
        return 0

    url = f"https://api.telegram.org/bot{TELEGRAM_BOT_TOKEN}/sendMessage"
    params = {
        # parse_mode : '',
        'chat_id': TELEGRAM_CHATID,
        'text': msg,
    }

    # Ignore response or error
    requests.get(url=url, params=params)
    return 0


def notify_reboot():
    return notify_send("Performing reboot, please re-start experiment!!")


def notify_stuck():
    if len (sys.argv) > 2:
        return notify_send("Power Meter is " + ' '.join(sys.argv[2:]))
    return notify_send("Power Meter is stuck!!")


def notify_finish():
    return notify_send("Experiments finished!!")


def notify_progress():
    if len(sys.argv) < 3:
        eprint("ERROR: Missing progress argument!")
        return 1

    progress = sys.argv[2]
    return notify_send(f'Current experiment progress {progress}')


def main():
    if len(sys.argv) < 2:
        eprint("ERROR: missing arguments!")
        return 1

    ACTIONS = {
        'progress': notify_progress,
        'stuck': notify_stuck,
        'reboot': notify_reboot,
        'finish': notify_finish,
    }

    action = sys.argv[1]
    if action not in ACTIONS:
        eprint(f"ERROR: unknown action: '{action}'")
        return 1

    return ACTIONS[action]()


if __name__ == "__main__":
    sys.exit(main())
