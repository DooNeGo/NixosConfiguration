---
paths:
  - "**/*.sh"
  - "**/*.zsh"
---

# Shell tools and CLI scripts

How to write a script or CLI tool kept in a `.sh` or `.zsh` file. The Nix module that builds it sits next to the file.

## Packaging

- Build it with `pkgs.writeShellApplication { text = builtins.readFile ./x.sh; runtimeInputs = [ … ]; }`: shellcheck runs on the real file at build time, and `errexit nounset pipefail` are set.
- Pass values from Nix as environment variables with `runtimeEnv`, named `<TOOL>_<NAME>`; the script reads them like any other variable. Do not substitute text into the file (`replaceVars`, `${…}`): shellcheck would stop seeing real code.
- Zsh code (a prompt hook) is read with `builtins.readFile`; the module may prepend a one-line variable definition. shellcheck does not parse zsh, so `scripts/lint.sh` runs `zsh -n` on it.
- Done when `scripts/lint.sh` exits 0 and the package builds with `nix build`.

## Command line

- `-h` and `--help` print to stdout and exit 0.
- A usage error prints `prog: reason` and `Try 'prog --help' for more information.` to stderr and exits 2. Runtime failures exit 1. Exit 2 is the convention of GNU tools, not a documented standard.
- Accept `--opt value` and `--opt=value`, end options at `--`, reject unknown options, and check that numbers are numbers.
- Strip control characters from text that is later printed to a terminal; the record may come from an untrusted unit.

## State

- Change shared state under `flock -w N` on a file descriptor, around the write only. A lock held across a slow call (a sink, a network request) stalls every other caller.
- Publish a file with a temp file in the same directory plus `mv`, so a reader never sees half a file.
- Test concurrency with parallel invocations on a temporary directory (`FAILURE_NOTIFY_DIR`-style override), then check that nothing was lost or corrupted.

## Completion

- Ship a zsh completion as `<dir>/_prog` (first line `#compdef prog`) in the same package under `share/zsh/site-functions`, and keep it in line with `--help`.
- Test it with `zmodload zsh/zpty` and a temporary `compinit -d <file>`, reading the pty in a `zpty -r -t` loop. Done when real Tab output lists the subcommands and the dynamic values.
- zsh caches completions in `~/.zcompdump*`; delete it after the first switch that adds a completion.

## Prompt hooks

- A hook runs before every prompt: builtins only, no forks.
- zsh differs from bash here: `printf '%(...)T'` is unsupported (use `strftime` from `zsh/datetime`), and an unmatched glob is an error (use `(N)`).
