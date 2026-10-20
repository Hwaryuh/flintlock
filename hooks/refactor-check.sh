#!/bin/sh
# Stop hook: once per change set, send Claude back to look for duplicated logic before it reports.
#
# Passes (exit 0) when: Claude is already continuing because of a stop hook, the project is not
# a git repository, nothing but docs/config changed, or this exact change set was already flagged.
# Otherwise blocks (exit 2): stderr goes to Claude as the reason to keep working.
# Run with --self-test to check the cases above in a throwaway repository.

# Docs and config never hold duplicated logic worth extracting. ':!' patterns match at any depth.
EXCLUDES="
:!*.md
:!*.mdx
:!*.txt
:!*.rst
:!*.json
:!*.jsonc
:!*.yml
:!*.yaml
:!*.toml
:!*.ini
:!*.cfg
:!*.lock
:!*.csv
:!*.svg
:!*.png
:!*.jpg
:!*.jpeg
:!*.gif
:!*.ico
:!LICENSE*
:!*.gitignore
:!*.gitattributes
"

check() {
  input=$(cat)
  # Second stop in a row: the reminder was already delivered, let Claude finish.
  printf '%s' "$input" | grep -Eq '"stop_hook_active"[[:space:]]*:[[:space:]]*true' && return 0

  cd "${CLAUDE_PROJECT_DIR:-.}" 2>/dev/null || return 0
  git_dir=$(git rev-parse --absolute-git-dir 2>/dev/null) || return 0
  # No commit yet: compare against the empty tree (hash depends on the repository's object format).
  base=$(git rev-parse -q --verify HEAD) || base=$(git hash-object -t tree --stdin </dev/null) || return 0

  set -f  # keep the * in $EXCLUDES away from the shell
  # shellcheck disable=SC2086
  files=$( { git -c core.quotepath=on diff --name-only "$base" -- . $EXCLUDES
             git -c core.quotepath=on ls-files --others --exclude-standard -- . $EXCLUDES; } 2>/dev/null)
  [ -n "$files" ] || return 0

  # Untracked files are not in `git diff`, so hash their contents too: a later edit to a new file
  # counts as a new change set.
  # shellcheck disable=SC2086
  digest=$( { git diff "$base" -- . $EXCLUDES
              printf '%s\n' "$files"
              git ls-files -z --others --exclude-standard -- . $EXCLUDES | xargs -0 git hash-object -- ; } 2>/dev/null |
            git hash-object --stdin)
  set +f

  stamp="$git_dir/flintlock-refactor-check"
  # ponytail: one stamp per repository (per worktree); sessions sharing a repo share the stamp.
  [ "$(cat "$stamp" 2>/dev/null)" = "$digest" ] && return 0
  printf '%s\n' "$digest" > "$stamp" 2>/dev/null || return 0  # can't remember it: don't nag every stop

  count=$(printf '%s\n' "$files" | wc -l | tr -d ' ')
  {
    echo "Refactor check: before you report, follow the flintlock:refactor-check skill for the changes below."
    echo "Changed files ($count):"
    printf '%s\n' "$files" | head -n 30 | sed 's/^/- /'
    [ "$count" -gt 30 ] && echo "- ... and $((count - 30)) more (git status)"
  } >&2
  return 2
}

self_test() {
  hook=$(cd "$(dirname "$0")" && pwd)/$(basename "$0")
  tmp=$(mktemp -d) || exit 1
  trap 'rm -rf "$tmp"' EXIT
  failed=0
  expect() {  # expect <exit code> <label> <stdin>
    printf '%s' "$3" | CLAUDE_PROJECT_DIR="$repo" sh "$hook" >/dev/null 2>&1
    got=$?
    if [ "$got" = "$1" ]; then echo "ok   $2"; else echo "FAIL $2 (exit $got, want $1)"; failed=1; fi
  }

  repo="$tmp/not-git"; mkdir -p "$repo"
  expect 0 "not a git repository" '{}'

  repo="$tmp/repo"; mkdir -p "$repo/src" "$repo/docs/deep"
  git -C "$repo" init -q
  git -C "$repo" -c user.name=t -c user.email=t@t commit -q --allow-empty -m init
  expect 0 "clean repository" '{}'

  echo 'notes' > "$repo/docs/deep/notes.md"
  echo '*' > "$repo/docs/deep/.gitignore"  # tools such as Serena drop these into projects
  expect 0 "only docs and config changed (nested)" '{}'

  echo 'int f(void) { return 1; }' > "$repo/src/a.c"
  expect 0 "stop_hook_active" '{"stop_hook_active": true}'
  expect 2 "code changed" '{"stop_hook_active":false}'
  expect 0 "same change set again" '{}'

  echo 'int g(void) { return 2; }' >> "$repo/src/a.c"
  expect 2 "untracked file edited again" '{}'

  mv "$repo/src/a.c" "$repo/src/b.c"
  expect 2 "untracked file renamed" '{}'

  echo 'x' >> "$repo/src/b.c"
  printf '%s' '{}' | CLAUDE_PROJECT_DIR="$repo" sh "$hook" 2>&1 >/dev/null | grep -q 'src/b.c' &&
    echo "ok   reason lists changed file" || { echo "FAIL reason lists changed file"; failed=1; }

  exit $failed
}

[ "$1" = "--self-test" ] && self_test
check
exit $?
