# Scripts

## How to run experiments:

By running `./scripts/start_experiment.sh` you stary an experiment in a new
screen. A check for whether an experiment is already running is performed.

To edit the properties of the experiment to run, you can edit them directly in
`multiple-experiment-wrapper.sh`. To edit the behavior of the experiment, edit
`tasks-run.sh`.

Scripts you should NOT invoke manually:
 - tasks-run.sh
 - start_experiment.sh
 - multiple-experiment-wrapper.sh
 - cpuonoff.sh
 - check_progress.sh
