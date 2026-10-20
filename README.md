# Flintlock

A Claude Code plugin that runs a refactor check after every task. When Claude is about to stop
and the git repository has changes it has not checked yet, Flintlock sends it back once to look
for duplicated logic in what it changed and to extract that logic on the second copy.

## Install

```
claude plugin install flintlock --marketplace Hwaryuh/flintlock
```

Or inside a session: `/plugin marketplace add Hwaryuh/flintlock`, then `/plugin install flintlock@flintlock`.

Requirements: `git`, and a POSIX `sh`. macOS and Linux have both. On Windows, install
[Git for Windows](https://git-scm.com/download/win), which includes Git Bash. Claude Code already
uses Git Bash for hooks when it is installed.

## How it works

The `Stop` hook (`hooks/refactor-check.sh`) runs each time Claude finishes a turn:

- It passes when the project is not a git repository, when nothing changed against `HEAD`
  (tracked changes and untracked files), or when only docs and config changed
  (`*.md`, `*.txt`, `*.json`, `*.yaml`, `*.toml`, lock files, images and similar).
- It passes when it already flagged this exact change set. It stores a hash of the change set in
  `.git/flintlock-refactor-check`. Nothing is written to your working tree.
- It passes when Claude is already continuing because of a stop hook, so it never loops.
- Otherwise it blocks the stop once. It tells Claude to follow the `flintlock:refactor-check`
  skill and lists the changed files.

The skill (`skills/refactor-check/SKILL.md`) is the procedure: for each changed function or block,
search the repository for the same logic. If this is the second copy, extract it. Keep behaviour
and passing tests. Then report one line about what was extracted, or that nothing was found.
If the change created a structural problem, such as a function that now does two jobs or code
left unused, Claude adds up to two one-line suggestions. It does not apply them: structural
changes are your call and belong in their own diff.
You can also run it by hand with `/flintlock:refactor-check`.

The check costs one extra turn per change set. A turn that only answers a question does not
trigger it again, unless the files changed.

## Turn it off

- Everywhere: `claude plugin disable flintlock@flintlock` (or `/plugin`, then the Installed tab).
- In one project only: add this to that project's `.claude/settings.local.json`:

  ```json
  { "enabledPlugins": { "flintlock@flintlock": false } }
  ```

- Remove it: `claude plugin uninstall flintlock@flintlock`.

## Develop

```
sh hooks/refactor-check.sh --self-test
claude plugin validate .
```

## License

MIT
