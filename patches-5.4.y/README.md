# How to Apply the Patches

The patches in this directory apply to kernel version 5.4.y.
The following is the description of the patches (by number):
 - 0001-0002: Must be applied only to ODROID platforms (can be applied for other
   platforms as well, but will be ignored when building the kernel);
 - 0003-0006: Patches to `schedutil` and to `SCHED_DEADLINE` to make them
   respect the choices of the user regarding the maximum CPU frequency (scaling
   now considers that instead of the CPU capability) and to ignore all
   non-deadline tasks when calculating the utilization of the system;
 - 0007-0021: Original APEDF implementation by Luca Abeni;
 - 0022-0028: Joined effort by Luca Abeni and Gabriele Ara to achieve a working
   version of APEDF.

To simplify referring to versions of the code, you can define the following
tags:
 - `apedf-base`: shall point to the commit immediately preceding 0001;
 - `apedf-global`: shall point to the commit defined in 0006;
 - `apedf-devel`: shall point to the last commit (can also be the branch all of
   these commit are applied on top).

To apply the patches simply use
```bash
git am -3k PATH_TO_THIS_DIR/*.patch
```
from within the kernel base directory and solve all of the issues that you
encounter (if any). Before running this command, define the `apedf-base` tag, so
that you do not have to add it manually later. To define the `apedf-global` tag
you can use the following command:
```bash
git tag -a apedf-global "$(git log --grep 'DEADLINE: Fix frequency scaling' --pretty=format:"%h")"
```

> NOTE: the `XX-walter` directory contains some more patches from a different
> version that is no longer in use, but may be useful in the future.