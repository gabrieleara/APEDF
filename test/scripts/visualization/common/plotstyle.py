#!/usr/bin/env python3

import matplotlib.pyplot as plt

def plot_setstyle(fig, axs):
	# TODO: do something here to change the style of the output
	pass

# def plot_figure
# def plot_figure(style_label=""):
#     """Setup and plot the demonstration figure with a given style."""
#     # Use a dedicated RandomState instance to draw the same "random" values
#     # across the different figures.
#     prng = np.random.RandomState(96917002)

#     fig, axs = plt.subplots(ncols=6, nrows=1, num=style_label,
#                             figsize=(14.8, 2.8), layout='constrained')

#     # make a suptitle, in the same style for all subfigures,
#     # except those with dark backgrounds, which get a lighter color:
#     background_color = mcolors.rgb_to_hsv(
#         mcolors.to_rgb(plt.rcParams['figure.facecolor']))[2]
#     if background_color < 0.5:
#         title_color = [0.8, 0.8, 1]
#     else:
#         title_color = np.array([19, 6, 84]) / 256
#     fig.suptitle(style_label, x=0.01, ha='left', color=title_color,
#                  fontsize=14, fontfamily='DejaVu Sans', fontweight='normal')

#     plot_scatter(axs[0], prng)
#     plot_image_and_patch(axs[1], prng)
#     plot_bar_graphs(axs[2], prng)
#     plot_colored_lines(axs[3])
#     plot_histograms(axs[4], prng)
#     plot_colored_circles(axs[5], prng)

#     # add divider
#     rec = Rectangle((1 + 0.025, -2), 0.05, 16,
#                     clip_on=False, color='gray')

#     axs[4].add_artist(rec)


# if __name__ == "__main__":

#     # Set up a list of all available styles, in alphabetical order but
#     # the `default` and `classic` ones, which will be forced resp. in
#     # first and second position.
#     # styles with leading underscores are for internal use such as testing
#     # and plot types gallery. These are excluded here.
#     style_list = ['default', 'classic'] + sorted(
#         style for style in plt.style.available
#         if style != 'classic' and not style.startswith('_'))

#     # Plot a demonstration figure for every available style sheet.
#     for style_label in style_list:
#         with plt.rc_context({"figure.max_open_warning": len(style_list)}):
#             with plt.style.context(style_label):
#                 plot_figure(style_label=style_label)

#     plt.show()
