#!/usr/bin/env python3

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
