# Flintlock

A Claude Code plugin that runs a refactor check after every task. When Claude is about to stop
and the git repository has changes it has not checked yet, Flintlock sends it back once to look
for duplicated logic in what it changed and to extract that logic on the second copy.

## Install

```
claude plugin install flintlock --marketplace Hwaryuh/flintlock
```

Or inside a session: `/plugin marketplace add Hwaryuh/flintlock`, then `/plugin install flintlock@flintlock`.

Codex CLI (untested): Codex reads Claude plugin manifests and hooks, so the same repository
should work there. Run `codex plugin marketplace add Hwaryuh/flintlock` and
`codex plugin add flintlock@flintlock`. Then open `codex`, run `/hooks`, and trust the Stop hook.
Codex does not run plugin hooks until you trust them.

Requirements: `git`, and a POSIX `sh`. macOS and Linux have both. On Windows, install
[Git for Windows](https://git-scm.com/download/win), which includes Git Bash. Claude Code already
uses Git Bash for hooks when it is installed.

## How it works

A `UserPromptSubmit` hook (`hooks/refactor-check.sh snapshot`) records the change set when a turn
starts, in `.git/flintlock-turn-<session id>`. The `Stop` hook (`hooks/refactor-check.sh`) runs each
time Claude finishes a turn:

- It passes when the project is not a git repository, when nothing changed against `HEAD`
  (tracked changes and untracked files), or when only docs and config changed
  (`*.md`, `*.txt`, `*.json`, `*.yaml`, `*.toml`, lock files, images and similar).
- It passes when the change set is the same as at the start of the turn, so a question, a review
  or an investigation never triggers it, even in a repository that was already dirty.
- It passes when it already flagged this exact change set. It stores a hash of the change set in
  `.git/flintlock-refactor-check`. Nothing is written to your working tree.
- It passes when Claude is already continuing because of a stop hook, so it never loops.
- Otherwise it blocks the stop once. It tells Claude to follow the `flintlock:refactor-check`
  skill and lists the changed files.

The skill (`skills/refactor-check/SKILL.md`) is the procedure: for each changed function or block,
search the repository for the same logic. If this is the second copy, extract it. Keep behaviour
and passing tests. Then report one line about what was extracted, or that nothing was found.
It also checks member placement: members Claude added, or whose access modifier it changed, go
where the type's member order puts them. The order comes from the project's linter config or
instructions first, then from the order the file already follows, then from a language default
(C#: StyleCop kind and access order; Java: Checkstyle field order, related methods together;
Kotlin: the official class layout, which does not order by visibility; TypeScript: the
typescript-eslint `member-ordering` default; JavaScript and others: the file's own order).
Only those members move.
Each moved existing member is named in the report with its modifier change, because a move hides
that change in the diff.
If the change created a structural problem, such as a function that now does two jobs or code
left unused, Claude adds up to two one-line suggestions. It does not apply them: structural
changes are your call and belong in their own diff.
You can also run it by hand with `/flintlock:refactor-check`.

The check costs one extra turn per change set. A turn that changes nothing does not trigger it.
If you or another session edit files while Claude is working, Flintlock counts that as Claude's change.

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
