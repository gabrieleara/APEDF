#!/usr/bin/env python3

import argparse
import os
import sys
import pandas as pd

from common.util import *
from common.plotstyle import *
from common.power import *

import warnings

def fig_show_or_savetotemp(fig):
    with warnings.catch_warnings(record=True) as w:
        # Cause all warnings to always be triggered.
        warnings.simplefilter("always")

        fig.show()

        if len(w):
            # We have a warning, let's plot to a tmp location
            fname = "/tmp/tmpfig.png"
            print(f"Saving output temporarily in {fname} ...")
            fig.savefig(fname)
        #--
    #--
#--


def main():
    data = pd.read_csv(sys.argv[1])
    fig, ax = plt.subplots()

    plot_power_time(fig, ax, data)
    fig_show_or_savetotemp(fig)
    return 0
#--

if __name__ == '__main__':
    sys.exit(main())
