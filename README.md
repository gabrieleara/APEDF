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
