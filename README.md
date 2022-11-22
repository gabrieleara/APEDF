# APEDF Implementation for `SCHED_DEADLINE`

This document illustrates the changes needed to implement Adaptively Partitioned
EDF (APEDF) with a First Fit (FF) task allocation strategy for the
`SCHED_DEADLINE` scheduling policy within the Linux kernel.

## Symbols and terminology used throughout this document

In the following, the `U` symbol refers to the utilization of the mentioned CPU
core and we assume that all cores have a maximum utilization (or capacity) equal
to `1`.

This assumption simplifies the exposition, but it is not very accurate for
systems in which different types of cores are present with different capacities
(namely big.LITTLE architectures), for which a different capacity value might be
needed. Since the capacity is defined in a per-core basis however, we can use
the number `1` and assume that a correct implementation will switch it for a
reasonable number depending on the core type.

## APEDF Core Principles

These core principles are described in the paper "Adaptive Partitioning of
Real-Time Tasks on Multiple Processors" by Luca Abeni and Tommaso Cucinotta
[[1]]. The following summarizes the main principles for the sake of the
exposition in this document:

 1. *Tasks Start on First Core* - All new task instances are initially allocated
    on the first core of the system (typically core 0).
 2. *Restricted Migration* - A task can be migrated only at the beginning of a
    new instance. If a task that wants to run under the `SCHED_DEADLINE` policy
    wakes up on a core with `U <= 1`, then the task is not migrated.
 3. *First Fit Migration* - A task that wakes up on an overloaded core (`U > 1`)
    will be migrated on a different core where the task is schedulable, i.e. `U
    <=1`  (if any can be found) using a First Fit (FF) strategy.
 4. *Fallback on Global EDF* - A task that needs to migrate to another core but
    cannot find any in which it might fit without incurring in a core overload
    should select a core based on Global EDF, i.e. it should select the core
    with the largest current deadline and migrate to that core, preempting the
    currently running task.

## The implementation

The companion project to this document implements the principles above. The
project is structured as follows:
```
.
├── patches
├── apedf-patches-apply.sh
├── apedf-patches-export.sh
└── ...
```

The [patches] directory contains a set of patches that can be applied on top of
any (recent) version of the Linux kernel automatically to implement APEDF for
`SCHED_DEADLINE`.

> However, the way it is implemented slightly deviates from the description
> above. In particular, **Core Principle 1** is violated by this implementation,
> which undermines the analysis provided by [[1]]. I will describe the reason
> why this principle is violated later in this document.

To apply the patches on top of any kernel version, follow these steps:

 1. Clone the kernel that you want to patch. The patches should work on many
    different kernel versions out of the box, but that's not guaranteed. The
    patches have been tested for compilation against the Linux kernel provided
    by HardKernel for the ODROID-XU4 board. This kernel can be cloned using the
    following command, which creates a new directory called
    `kernel-odroid-5.4.y` with a shallow clone of the kernel:

```bash
git clone --depth 1 --branch=odroid-5.4.y https://github.com/hardkernel/linux kernel-odroid-5.4.y
```

 2. Whatever kernel you cloned, move to its directory (e.g., ``) and run the
    `apedf-patches-apply.sh` script. This script will attempt to apply the
    patches one by one on top of the current kernel directory.

```bash
cd kernel-odroid-5.4.y
../apedf-patches-apply.sh
```

 3. On success, the following is the git commit graph that you will end up with:

```txt
git log --oneline --all --graph

* 1a2782181 (HEAD -> apedf-devel, tag: development) Change extraversion
* 12be05848 Changes for experimentations on ODROID board
* 66faed0e9 Any pushable dl task may be pushed
* b961c3a9e (tag: apedf-abeni) [PATCH 10/10] Misc fixes
* 85092c9bf [PATCH 09/10] remove useless check
* bea9d5244 [PATCH 08/10] fix find_lock_later_rq
* bd699be38 [PATCH 07/10] Fix bug in push_dl_task: get the task structure when
            needed
* b93024e2d [PATCH 06/10] Account for the cores' capacity in asymmetric systems
* 0ef882470 [PATCH 05/10] Remove probably unneeded code
* 16a35d662 [PATCH 04/10] Respect sched_rt_{runtime,period}_us
* baa8d9a70 [PATCH 03/10] Add apedf extraversion
* 5b64376cc [PATCH 02/10] Fix the next bug, in the FF algorithm
* 92989e174 [PATCH 01/10] Revised APEDF implementation, draft 1
* 80f620525 (tag: energy-exynos) [PATCH 2/2] ARM: exynos_defconfig: Enable
            SCHED_MC and ENERGY_MODEL
* 65dd85ccd [PATCH 1/2] ARM: dts: exynos: Add dynamic-power-coefficient to
            Exynos5422 CPUs
* e04a0f0fd (grafted, tag: apedf-begin, [...]) Kconfig: char: fix merge error
```

The following git tags (part of the new `apedf-devel` branch) will be provided:

- `apedf-begin`: Marks the commit that was `HEAD` before the patches were
  applied.
- `energy-exynos`: Marks the two patches that come directly from the mainline
 Linux kernel that need to be applied only on the kernel for the ODROID-XU4.
 These patches are NOT automatically applied on any kernel (modify the
 `apedf-patches-apply.sh` script to enable them).
- `apedf-abeni`: Marks the 10 patches implemented by Luca Abeni to implement
 APEDF on top of `SCHED_DEADLINE`. This document will not discuss the changes
 introduced by those patches, but only the issues related to them and the
 fixes implemented on top of this version.
- `development`: Marks the end of the patches developed for this project.

> Unfortunately, the patches seem to clash with the current 6.0 version of the
> mainline Linux kernel. However, the script provided in this folder will help
> you apply them on top of any kernel (with some minor changes). In case of
> failure, the script will generate a set of `*.rej` files that you can easily
> find using `find -name '*.rej'`. Use the information contained in those files
> to manually edit the patches in the [patches] directory. Before running the
> script again, delete all the rejected files (`find -name '*.rej' -delete`) and
> abort the rebase started by the script by runinng `git am --abort`. Repeat
> this process until all of the commits above are applied on top of your Linux
> kernel clone.

## Issues in `apedf-abeni`

If you select the APEDF implementation in `apedf-abeni`, there are a few issues
related to how it implements the core principles described above.

### Incorrect Task Push Implementation

The `push_dl_task` function is incorrectly implemented. The minimal changes made
to this function make it impossible to push a task that has is not the one with
the earliest deadline among the pushable ones on the runque. The commit "*Any
pushable dl task may be pushed*" fixes this issue, pushing any task in the
pushable list (tree) if necessary, not only the first one. The commit also fixes
some other minor issues in other parts of the code that do not have a big impact
on the overall behavior of the system.

### Core Principle 1 and 2 are NOT correctly implemented

The implementation provided with those 10 patches relies on the wrong assumption
that upon first wakeup a task that switched to `SCHED_DEADLINE` will begin
execution on core 0. This assumption is wrong. In reality, at least in Linux
kernel version 5.4, a task that performs a `sched_setscheduler` syscall will
remain on the same CPU core it was previously running under a different
scheduling policy. Typically, this policy is CFS (or `SCHED_OTHER`).

This can be proved by looking at the code of `sched/core.c` and via experimental
testing. Starting several mockup tasks like the following one will easily show that the tasks are kept on where originally CFS scheduled them. Since no tasks will migrate if they fit on the core they are running on (**Core Principle 2**), they will be kept indefinitely on the same core.

```bash
# Start a periodic task with utilization 1/5 in background
chrt -d -P 500000000 -T 100000000 0 yes >/dev/null &
```

The `select_task_runqueue_dl` function should select the core on which a task
will start execution on wakeup (using FF). However, that function is called only
on task wakeup from a blocking call. Tasks started like the code above will
never block and thus will never invoke the `select_task_runqueue_dl`. There is only one exception and that is the first ever task that you run using that command. This because the code for the `yes` program has to be loaded from the file system into main memory (thus blocking temporarily the task) upon performing `exec`.

This can again be proved very easily by tracing the calls to `select_task_runqueue_dl` and running the following snippet:
```bash
# Start first task, if this is the first `yes` instance called from boot it will
# call select_task_runqueue_dl
chrt -d -P 500000000 -T 100000000 0 yes >/dev/null &
sleep 5s
# Terminate the previous command
pkill yes

# Start a second task, no call to select_task_runqueue_dl this time
chrt -d -P 500000000 -T 100000000 0 yes >/dev/null &
sleep 5s
pkill yes

# Drop the cache, dropping also the code for the yes command since none is in execution
sync; echo 1 > /proc/sys/vm/drop_caches

# A-ah! select_task_runqueue_dl is invoked again on waekup!
chrt -d -P 500000000 -T 100000000 0 yes >/dev/null &
sleep 5s
pkill yes
```

What's more, the code of `select_task_runqueue_dl` is in itself problematic (see
comments):
```c

static int select_task_rq_dl(struct task_struct *p, int cpu,
    int sd_flag, int flags)
{
    struct rq *rq;
    int target;

    // This line prevents calls on exec to change the location of the task,
    // which we are fine with
    if (sd_flag != SD_BALANCE_WAKE)
        goto out;

    rq = cpu_rq(cpu);

    // This line prevents tasks that are not active contenting (aka any
    // task on first wakeup) to be assigned a runqueue
    if (p->dl.dl_non_contending)
        goto out;

    // If we get here this might be a different activation than the first
    // one, but if the task fits on the current core it should NOT be
    // migrated to another one! Instead we always try to "pack" tasks into
    // the first cores using FF on each wakeup from a blocking call!
    rcu_read_lock();
    target = find_later_rq_ff(p);
    if (target >= 0) {
        cpu = target;
        /// [...]
    }
    rcu_read_unlock();

out:
    return cpu;
}
```

As you can see, the implementation of this method is not only flawed, it is also
not trivial how to fix this:

- If we want to implement **Core Principles 1 and 2**, an okay way to fix this
 method is to return 0 only if the task has not been previously scheduled with
 `SCHED_DEADLINE` before and always keep it on the same core on which it is
 running otherwise (it will be pushed somewhere else if it does not fit).
- However, this method is not called in many paths followed by the kernel when
 a task switches to `SCHED_DEADLINE`, so this does not solve the issue of
 **CP1** in most scenarios.

Another point in which it might be better to perform the task placement is
perhaps the `switched_to_dl` function. However, that has another problem. The
`switched_to_dl` function is called for when the *current* task switches to
`SCHED_DEADLINE`. We cannot drop the lock on the current runqueue to attempt a
task migration in `switched_to_dl`, which means that we have to rely on a
balance callback to perform the migration, which may be fine. However, we cannot
migrate the *current* task in execution to a different core, not even in a
balance callback (or, at least, I am not aware of a way to safely push away the
*current* task in a rq).

So there is not an easy way to implement **Core Principle 1 and 2** without
migrating the task that might be the *current* one on a runqueue. Perhaps, a
task might run the first time on the core it was running previously under CFS
and migrate on its second activation, but that deviates from the core principles
in a different way and it might require an analysis.

### Best Fit-like behavior

Since basically all tasks start from cores on which they were originally
scheduled by CFS and never migrate if they still fit on their current core, the
allocation strategy that is actually implemented is remarkably similar to Best
Fit, instead of First Fit. This because CFS tends to prefer running tasks on
less loaded cores and if the tasks running under `SCHED_DEADLINE` consume a
considerable amount of bandwidth for each core (like the example above), new
tasks will begin running on the less loaded cores.

## Conclusions

In general, the implementation of APEDF is not conforming to the core principles
described in [[1]] and needs some work so that it will conform to what we
expect.

The project provides also some scripts for running tests on the provided
implementation of APEDF. However, I did not run the experiments on the "fixed"
implementation provided here, as it is not exactly correct.

----

## References

[[1]] : Abeni, Luca, and Tommaso Cucinotta. "*Adaptive partitioning of real-time
tasks on multiple processors.*" Proceedings of the 35th Annual ACM Symposium on
Applied Computing. 2020. [DOI: 10.1145/3341105.3373937][1-link]


<!-- Links -->

[patches]: ./patches

[1]: #references
[1-link]: https://dl.acm.org/doi/pdf/10.1145/3341105.3373937
