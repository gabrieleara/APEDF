# APEDF Implementation for `SCHED_DEADLINE`

This document describes how to get the APEDF patch for `SCHED_DEADLINE` up and
running quickly with a compatible kernel.

# Patching a kernel

You can download a kernel like usual inside this repository and then patch it
using the tools provided by this repo.

To clone a kernel use (example for a Raspberry PI kernel compatible with a
Raspberry PI 4):
```bash
mkdir -p kernels
git clone --depth 1 --branch 1.20221104 \
	https://github.com/raspberrypi/linux.git \
	kernels/rpi-5-15-1.20221104
```

Where `kernels/rpi-5-15-1.20221104` is the path where the kernel will be downloaded.

To patch a kernel run the following commands:
```bash
cd kernels/rpi-5-15-1.20221104 # or any directory where the kernel resides
../../apedf-patches-apply.sh
```

The script will attempt to patch the kernel. If it fails at some point, you can
manually edit the files and continue the patching process using
```bash
git am --continue
```
after staging your changes.

> **NOTE**: The script may be interrupted at two key points: before creating the
> git tag named `apedf-abeni` or after.
> - If it is interrupted before and you finished patching using the command
> above, please create the tag using `git tag -a apedf-abeni` and then run again
> the script as before.
> - If it is interrupted after, finish patching and then run `git tag -a
> development`. This is useful for both the patching script and the export
> script.
>
> Repeat until you get a full run without errors.

At the end of the process, your git history should look something like this when
queried inside the kernel directory (again, the mentioned RPI4 kernel is used
for reference):
```txt
* e7d232f97 (HEAD -> apedf-devel, tag: development) Placing non contending tasks in DL timer
* 10e4eb590 Fix DL: Keep looking for new pushable tasks
* 1cda52903 [PATCH 2/2] Try to fix the "migrate on unthrottling" case
* 4815a9eb2 [PATCH 1/2] Try to fix the issue with tasks "borning" on the wrong CPU core
* a9568e9a4 [PATCH 3/3] Any pushable dl task may be pushed
* 66128d2e9 [PATCH 2/3] Queue a push when a task misses a deadline
* 676351185 [PATCH 1/3] Split pick_next_pushable_dl_task() into multiple functions
* 1efaeddc8 (tag: apedf-abeni) [PATCH 10/10] Misc fixes
* 9b7f611d2 [PATCH 09/10] remove useless check
* f507b3a93 [PATCH 08/10] fix find_lock_later_rq
* 739d8bb84 [PATCH 07/10] Fix bug in push_dl_task: get the task structure when needed
* 40f06d2f5 [PATCH 06/10] Account for the cores' capacity in asymmetric systems
* 9d459d20b [PATCH 05/10] Remove probably unneeded code
* 71db7b771 [PATCH 04/10] Respect sched_rt_{runtime,period}_us
* 2ddc622ed [PATCH 03/10] Add apedf extraversion
* f56dbfc7b [PATCH 02/10] Fix the next bug, in the FF algorithm
* 4bb1db544 [PATCH 01/10] Revised APEDF implementation, draft 1
* 45d339389 (grafted, tag: apedf-begin, tag: 1.20221104) drm/connector: Set DDC pointer in drmm_connector_init
```

# Building and installing the kernel

To simplify the build process for some reference platforms, a build script and
an install script are provided. For info about the various arguments accepted by
each script invoke them with `--help`.

The most important parameter is `--target` which will change the behavior of the
script to adapt to the requirements of the selected board. Given a target, the
scripts auto-detect whether you run them on a compatible host or if you need to
cross compile everything. For cross compilation, they rely on:
 - `aarch64-linux-gnu-gcc` for arm64 boards
 - `arm-linux-gnueabihf-gcc` for arm (v7) boards

In general, you can install the dependencies of the build and install script by
running:
```bash
apt-get install -y \
	--no-install-recommends \
	git bc bison flex libssl-dev make libc6-dev libncurses5-dev kmod \
	crossbuild-essential-armhf \
	crossbuild-essential-arm64 \
	sshfs
```
It should be straightforward what most of these dependencies are. `sshfs` is
used to install a kernel on a remote host via SSH and it is not necessary to
build a local image.

> While I haven't tested this, you could build a kernel for your current machine
> without supplying a --target parameter. Note that arm devices are picky,
> thought, and they often need special parameters to be built correctly (hence
> the --target parameter).
>
> You should be fine if you try to build a x86-64 on a x86-64 machine without
> supplying the --target parameter. If you test it let me know.

Be careful when you use the command to install the kernel because you might end
up overwriting existing ones. For now, there is no parameter to change the name
of the kernel image file generated.

## Examples for the RPI4

To build the kernel patched before run (in whatever directory you like):
```bash
./scripts/kernel-build.sh \
	--srcdir kernels/rpi-5-15-1.20221104 \
	--target rpi4 \
	--config defconfig
```

To install it on a RPI4 connected over the network you can use the following
command:
```bash
./scripts/kernel-install.sh \
	--srcdir kernels/rpi-5-15-1.20221104 \
	--remote root@10.30.3.197 \
	--target rpi4
```

Upon connecting to the remote host via ssh, you will be prompted (once per
install) for the SSH password by `sshfs` if necessary.

> To speed up the installation process, you can skip the installation of kernel
> modules by supplying the `--skip-modules` option. This is useful if you for
> instance build multiple times kernels with the same `uname -r` and you don't
> need to copy each time the kernel modules.

To install a kernel locally (i.e. on your local machine), simply do not provide
the `--remote` option (dangerous!).

# Running experiments

## Installing dependencies

Dependencies of the tests can be installed using the following line:
```bash
apt-get install -y \
	rsync \
	cpufrequtils \
	lm-sensors \
	automake \
	git \
	libtool \
	libjson-c-dev
```

## Copying the project on the target

You can clone the project on the target machine of course, but if you work on a
computer you might prefer to simply copy all the files on the target instead
after making your changes.

To do so, you can use `rsync` from the root of the project like so:
```bash
rsync -aviz "$PWD" root@REMOTE_HOST: \
	--include='**.gitignore' \
	--exclude='/.git' \
	--filter=':- .gitignore' \
	--delete-after
```
where REMOTE_HOST is the address of the target machine (requires `rsync`
installed on the target).

We use the `root` user now for reasons that will become clear in a moment.

## Other Prerequisites for running the experiments

While being not strictly mandatory, we recommend stopping all unwanted processes
on the target host before running experiments.

> For now, no power measurements are made during experiments, however, doing
> this step would be very beneficial if we were doing power measurements.

To do so, you can leverage the `rescue-ssh` systemctl target, present on typical
debian distribution, which shuts off all services except the SSH server. To do so, run
```bash
systemctl isolate rescue-ssh
```

The following is the list of processes (excluding kernel threads) running on a
RPI4 target after isolating the given target:
```txt
echo q | htop -C -t | tail -n +2

    0[                         0.0% 1000MHz 41°C]   Tasks: 12, 1 thr; 1 running
    1[                         0.0% 1000MHz 41°C]   Load average: 0.02 0.03 0.00
    2[                         0.0% 1000MHz 41°C]   Uptime: 00:02:48
    3[                         0.0% 1000MHz 41°C]
  Mem[|#*                            69.6M/3.71G]
  Swp[                                     0K/0K]

    PID△USER      PRI  NI  VIRT   RES   SHR S CPU% MEM%   TIME+  Command
      1 root       20   0  161M 10400  7460 S  0.0  0.3  0:03.14 /sbin/init
    145 root       20   0 32728 12472 11560 S  0.0  0.3  0:00.79 ├─ /lib/systemd/systemd-journald
    167 root       20   0 21620  6032  3828 S  0.0  0.2  0:00.66 ├─ /lib/systemd/systemd-udevd
    322 systemd-t  20   0 88108  5980  5248 S  0.0  0.2  0:00.31 ├─ /lib/systemd/systemd-timesyncd
    359 systemd-t  20   0 88108  5980  5248 S  0.0  0.2  0:00.01 │  └─ sd-resolve
    501 root       20   0  5476  1460  1356 S  0.0  0.0  0:00.00 ├─ /sbin/agetty -o -p -- \u --noclear t
    529 root       20   0 13652  6404  5536 S  0.0  0.2  0:00.03 ├─ sshd: /usr/sbin/sshd -D [listener] 0
    599 root       20   0 16072  7776  6568 S  0.0  0.2  0:00.40 │  └─ sshd: root@pts/0
    620 root       20   0  9840  4528  3012 S  0.0  0.1  0:00.11 │     └─ -bash
    702 root       20   0  8352  3668  2656 R  0.0  0.1  0:00.05 │        ├─ htop -C -t
    703 root       20   0  6860   508   444 S  0.0  0.0  0:00.00 │        └─ tail -c +2
    602 root       20   0 15916  7616  6444 S  0.0  0.2  0:00.13 └─ /lib/systemd/systemd --user
    603 root       20   0 95344  4664  1660 S  0.0  0.1  0:00.00    └─ (sd-pam)

```

> Side effect of this systemctl target is that only root is granted access to
> the machine via SSH when in this mode. You can bypass this problem by changing
> the content of some files, but it is easier to connect via root (and the
> script to run the experiments will have to be executed using sudo anyway!).

To get back to the original set of services running after you are done with
experiments, run
```bash
systemctl isolate $(systemctl get-default)
```

## Running the experiments

The project contains a `tasksets` directory, which contains a set of
automatically generated tasksets. These tasksets differentiate depending on:
 - number of tasks in the set (6, 8, 12, 16)
 - system uilization (from 1.0 to 3.6)

For each of these combinations (85), 10 unique tasksets are generated, for a
total of 850 tasksets. Different tasksets can be generated using an automated
script (instruction will follow in another commit).

The script that will run the experiments is in `scripts/tasks-run.sh`, which
accepts a variety of options:
```txt
./scripts/tasks-run.sh --help

Usage: tasks-run.sh <options>

    --skipbuild         - skips the build of the apps (e.g., rtapp)
    --printlist         - print the full ordered list of tasksets

    --tasksdir=TASKSDIR - the directory where to look for tasksets; it will
                          look only for tasksets in that directory, meaning
                          no subdirectories!
                          (default = CWD)
    --outdir=OUTDIR     - the directory where to put all output files
                          (default = CWD/out)
    --loglevel=LOGLEVEL - the log level to use when running rt-app
                          (default = 10)
    --rtlimit=RTLIMIT   - value to write in 'kernel.sched_rt_runtime_us'; use -1
                          to disable the runtime limit for rt apps
                          (default: no value will be written)
    --cooldown=SECONDS  - time to sleep for in-between runs for cooldown
                          (default: 90s)
    --maxfreq=MAXFREQ   - maximum frequency to set (using 'performance'
                          governor), value expressed either in Hz or by using
                          unit suffixes (e.g., 1.4GHz); by default, the maximum
                          frequency accepted by core 0 is used
                          (in this case, 1500000 HZ)

    -h --help           - show this help message and exit
    --debug             - run this program in debug mode

```

The default options should be fine. If you installed all dependencies, running
the script with default options will build from sources `rt-app`, select the
maximum frequency the CPU can run at and the `performance` CPUFreq governor, and
it will then start running each taskset one by one.

Experiments are executed by increasing number of tasks and decreasing value for
utilization. Use `--printlist` to see the order in which experiments will be
executed.

I suggest using at least option `--tasksdir` to select the `tasksets` directory,
like so:
```bash
./APEDF/scripts/tasks-run.sh --tasksdir tasksets
```

Output will be something like this (on RPI4):
```txt
 + Re-building apps (just in case) ...
 + clean rtapp...
 + build rtapp
 ... <omitted output of automake>
 + setting maximum frequency and governor...
 + advertised frequency configuration:
          minimum CPU frequency  -  maximum CPU frequency  -  governor
CPU  0       600000 kHz ( 40 %)  -    1500000 kHz (100 %)  -  performance
CPU  1       600000 kHz ( 40 %)  -    1500000 kHz (100 %)  -  performance
CPU  2       600000 kHz ( 40 %)  -    1500000 kHz (100 %)  -  performance
CPU  3       600000 kHz ( 40 %)  -    1500000 kHz (100 %)  -  performance

 + Starting tests...

 + Running test [001/850] defined in /root/APEDF/tasksets/ts_n06_i00_u1.0000.json ...
 + Running test [002/850] defined in /root/APEDF/tasksets/ts_n06_i01_u1.0000.json ...
 ...<other experiments will follow>
```
