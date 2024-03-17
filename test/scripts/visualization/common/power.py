#!/usr/bin/env python3

import matplotlib.pyplot as plt

def plot_power_time(fig, ax, data):
	# Fields:
	# - timestamp
	# - voltage_mV
	# - current_mA
	# - power_mW
	# - onoff
	# - interrupts

	ax.plot(data['power_mW'])
#-- plot_power_time()
