# Snake-tools

Some snakes get sad when they have to use `cut` or `killall` and it doesn't do what they want. This repository is for such snakes.

## Goal

Replacement for some coreutils or busyboxutils that are not very useful in their original form. Shortlist:
- [x] `cut`
    - Cut splits by tab on default, and we cannot make it split on multiple characters. This is pretty useless since most tools output space-delimited data. Even in those cases, it doesn't properly work. The `cut` replacement (`fields`) splits on whitespace by default.
- [ ] `killall` / `kill`
    - killall is just useless. I type `killall firefox` and nothing happens. The replacement should match on argv[0] instead. The idea is to write a `kill` alternative (`unalive`) that takes a list of PIDs from stdin.
