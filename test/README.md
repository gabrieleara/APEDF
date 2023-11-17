# Testing Utilities for AP-EDF

This directory contains some testing utilities for evaluating the performance
our AP-EDF variant compared to default `SCHED_DEADLINE`.

The structure of this directory is the following:

- [apps]: contains two applications (rt-app and power-sampler) that are used to
  simulate tasks for execution and collect power metrics. If you do not see this
  directory or its contents, clone again this repo and/or initialize git
  submodules.
- [out]: output of the evaluation, it will be created and filled automatically
  during testing/data collection and visualization.
- [scripts]: contains utilities used by the software tools in this directory.
- [tasksets]: contains a set of tasks used to evaluate scheduling performance.

The following tools are also included in this directory; their usage will be
explained in later sections:

- `collect.sh`
- `generate.sh`
- `kernel-build.sh`
- `kernel-install.sh`
- `plot.sh`
- `test-on-remote.py`
- `test.sh`

## Building/installing a kernel

You probably already know how to patch and build a kernel, but if you need any
help (for example when cross-building a kernel for a specific board) you can
check out the `kernel-build.sh` and `kernel-install.sh` scripts. They provide
some helpful output for usage.

## Generating the tasksets

This is the first step to evaluate the various schedulers. This project comes
already with a set of tasksets ready to be evaluated in the [tasksets]
directory.

To re-generate them, you can use the `generate.sh` script. To facilitate the
generation of different tasksets using certain parameters, you can edit the
script and change manually the `GT_*` options, which drive the script execution.
You can then re-generate the content of the [tasksets] directory by running
`generate.sh` without arguments.

> __NOTICE__: `generate.sh` does not perform any cleanup, it only adds files to
> the output directory (by default [tasksets]). If you want to remove all older
> files delete the [tasksets] directory altogether or its contents before
> running the script.

Alternatively, you can edit the options in [tasksets/params.sh] script and run
the following command:
```bash
./generate.sh tasksets/params.sh
```

> __NOTICE__: again, if you want to remove older files delete them before
> executing the script, but remember to keep the `params.sh` file around!

## Testing the scheduler

Once you have your kernel images ready and you generated your tasksets it is
time to test the multiple scheduler variants (global/default `SCHED_DEADLINE`,
AP-EDF with First-Fit, AP-EDF with Worst-Fit).

To do this, you can use the `test.sh` script, which will configure the current
platform for testing and iterate over all tasksets, executing them one by one.
This is the most delicate part of the process: the `test.sh` script has been
tested only on a specific platform, so it may not work as intended on your
machine. I suggest you check the code before you execute it if you can. It is
quite large (~700 loc), but it is also written to be as comprehensible as
possible.

Test parameters are available for editing at the top of the script, to avoid
parsing many command-line arguments on execution.

One prerequisite of the script is that multiple kernel images should be
installed in the `kernels` folder inside this directory, which is not present by
default. Build your scheduler variants and copy them in the `kernels` directory
so that you end up with the following structure:
```txt
./kernels
├── apedf-ff.zImage
├── apedf-wf.zImage
└── global.zImage
```

> __NOTICE__: the `test.sh` script __WILL__ reboot your machine multiple times,
> switching between different kernels as it goes through the various
> combinations of scheduler variant, schedutil governor and taskset. A reboot
> may happen as soon as you start the experiments if the first kernel it wants
> to test is not the one currently executing on your machine. You have been
> warned!

Then, you can start the experiments by executing
```bash
./test.sh start
```
The tests will execute in the background and print out some logs in
`last_experiment.log`. To check the progress of your experiments, run:
```bash
./test.sh check_progress
```

During tests execution, the machine may be rebooted multiple times. Each time it
is rebooted, you must re-start the experiments by executing again
```bash
./test.sh start
```
Don't worry about losing your data: the script automatically skips all
successful executions of each combination of scheduler variant, schedutil
governor and individual taskset. Basically, it resumes from where it left off
before rebooting. This is useful also in the remote case of a crash, you can
keep going from where you last crashed. Data should not be corrupted in case of
crashes, thanks to the way experimental outcomes are saved to disk.

Since restarting the `test.sh` script for each reboot is annoying and
time-consuming (especially if tests take several days!), a separate script
called `test-on-remote.py` is provided. This script must be executed on a
different machine from the one you are testing: it will log into the other
machine via SSH (granted you set up automatic login via SSH keys), it will
periodically check the test progress, and it will restart the `test.sh` script
after reboots. You can even get notified via Telegram on the progress! Again,
configuration parameters for the script is at the very beginning of the code, so
you don't have to provide any command-line arguments and just run
```bash
./start-on-remote.py
```

> If you do not want to keep two copies of the APEDF project, you can just copy
> the python script on your other machine. The full APEDF project should be
> installed on the testing device though! And its path must be updated in the
> `APEDF_PATH` variable in the Python script.

## Collecting and plotting test results

Once all tests are over, you can collect statistics on task execution using the following command:
```bash
./collect.sh out
```
where `out` is the output directory of your testing. The utility will collect
all available data into convenient CSV tables for you to inspect.

> You can change this directory using configuration parameters. I will keep
> referring to the `out` directory in the future though, so you should
> substitute your own output directory name in following commands.

Once the script is over you can produce various plots in the same `out` directory using
```bash
./plot.sh out
```

<!------ LINKS ------>

[apps]: apps
[out]: out
[scripts]: scripts
[tasksets]: tasksets
[tasksets/params.sh]: tasksets/params.sh
