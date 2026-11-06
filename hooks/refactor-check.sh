#!/bin/sh
# Flintlock hook, two modes:
#
#   snapshot  (UserPromptSubmit) records the change set as it is when a turn starts, per session.
#   (default) (Stop) once per change set, sends Claude back to look for duplicated logic before it reports.
#
# The Stop mode passes (exit 0) when: Claude is already continuing because of a stop hook, the project
# is not a git repository, nothing but docs/config changed, the change set is the same as at the start
# of this turn (a turn that changed nothing), or this exact change set was already flagged.
# Otherwise it blocks (exit 2): stderr goes to Claude as the reason to keep working.
# Without a snapshot (older install, no session id) the "same as at turn start" check is skipped.
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

# Per-session turn snapshots live next to the stamp, in the git directory: $git_dir/$TURN_PREFIX<session id>.
TURN_PREFIX=flintlock-turn-

# Reads the hook input given as $1 and prints the session id, reduced to characters safe in a file name.
session_id() {
  printf '%s' "$1" |
    sed -n 's/.*"session_id"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -n 1 | tr -cd 'A-Za-z0-9_-'
}

# Sets $git_dir, $files and $digest for the current project. Returns 1 when the project is not a git
# repository or has no changes worth checking; then $digest is "none" (and $git_dir is empty if not git).
# Returns 2 when git could not tell (no base to compare against): the result is unknown, not "no changes".
scan() {
  git_dir=
  files=
  digest=none
  cd "${CLAUDE_PROJECT_DIR:-.}" 2>/dev/null || return 1
  git_dir=$(git rev-parse --absolute-git-dir 2>/dev/null) || { git_dir=; return 1; }
  # No commit yet: compare against the empty tree (hash depends on the repository's object format).
  base=$(git rev-parse -q --verify HEAD) || base=$(git hash-object -t tree --stdin </dev/null) || return 2

  set -f  # keep the * in $EXCLUDES away from the shell
  # shellcheck disable=SC2086
  files=$( { git -c core.quotepath=on diff --name-only "$base" -- . $EXCLUDES
             git -c core.quotepath=on ls-files --others --exclude-standard -- . $EXCLUDES; } 2>/dev/null)
  if [ -z "$files" ]; then set +f; return 1; fi

  # Untracked files are not in `git diff`, so hash their contents too: a later edit to a new file
  # counts as a new change set.
  # shellcheck disable=SC2086
  digest=$( { git diff "$base" -- . $EXCLUDES
              printf '%s\n' "$files"
              git ls-files -z --others --exclude-standard -- . $EXCLUDES | xargs -0 git hash-object -- ; } 2>/dev/null |
            git hash-object --stdin)
  set +f
  return 0
}

# UserPromptSubmit: remember the change set at the start of the turn. Prints nothing (stdout would
# reach Claude's context) and never blocks.
snapshot() {
  sid=$(session_id "$(cat)")
  [ -n "$sid" ] || return 0
  scan; scan_rc=$?
  # Not a git repository, or git failed: keep the previous snapshot rather than record a guess.
  [ -n "$git_dir" ] && [ "$scan_rc" -ne 2 ] || return 0
  printf '%s\n' "$digest" > "$git_dir/$TURN_PREFIX$sid" 2>/dev/null
  # Sessions come and go; drop snapshots nobody has touched for a week.
  find "$git_dir" -maxdepth 1 -name "$TURN_PREFIX*" -mtime +7 -exec rm -f {} + 2>/dev/null
  return 0
}

check() {
  input=$(cat)
  # Second stop in a row: the reminder was already delivered, let Claude finish.
  printf '%s' "$input" | grep -Eq '"stop_hook_active"[[:space:]]*:[[:space:]]*true' && return 0

  scan || return 0

  # Nothing changed since this turn started: a question, a review, an investigation. Not Claude's change set.
  sid=$(session_id "$input")
  if [ -n "$sid" ] && [ "$(cat "$git_dir/$TURN_PREFIX$sid" 2>/dev/null)" = "$digest" ]; then
    return 0
  fi

  stamp="$git_dir/flintlock-refactor-check"
  # ponytail: one stamp per repository (per worktree); sessions sharing a repo share the stamp.
  [ "$(cat "$stamp" 2>/dev/null)" = "$digest" ] && return 0
  printf '%s\n' "$digest" > "$stamp" 2>/dev/null || return 0  # can't remember it: don't nag every stop

  count=$(printf '%s\n' "$files" | wc -l | tr -d ' ')
  {
    echo "Refactor check: before you report, follow the refactor-check skill (flintlock:refactor-check in Claude Code) for the changes below."
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
  expect() {  # expect <exit code> <label> <stdin> [hook argument]
    printf '%s' "$3" | CLAUDE_PROJECT_DIR="$repo" sh "$hook" $4 >/dev/null 2>&1
    got=$?
    if [ "$got" = "$1" ]; then echo "ok   $2"; else echo "FAIL $2 (exit $got, want $1)"; failed=1; fi
  }

  repo="$tmp/not-git"; mkdir -p "$repo"
  expect 0 "not a git repository" '{}'
  expect 0 "snapshot outside a git repository" '{"session_id":"s1"}' snapshot

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

  # Per-turn snapshots, in a repository that has not flagged anything yet.
  repo="$tmp/turns"; mkdir -p "$repo/src"
  git -C "$repo" init -q
  git -C "$repo" -c user.name=t -c user.email=t@t commit -q --allow-empty -m init
  echo 'int f(void) { return 1; }' > "$repo/src/a.c"   # already there when the session starts
  expect 0 "snapshot records the turn start" '{"session_id":"s1"}' snapshot
  expect 0 "question-only turn on a dirty tree" '{"session_id":"s1"}'
  echo 'int g(void) { return 2; }' >> "$repo/src/a.c"
  expect 2 "edited during the turn" '{"session_id":"s1"}'
  expect 0 "same change set again (session)" '{"session_id":"s1"}'
  expect 0 "snapshot of the next turn" '{"session_id":"s1"}' snapshot
  expect 0 "next question-only turn" '{"session_id":"s1"}'
  echo 'int h(void) { return 3; }' >> "$repo/src/a.c"
  expect 2 "other session without a snapshot still checks" '{"session_id":"s2"}'

  exit $failed
}

case "$1" in
  --self-test) self_test ;;
  snapshot) snapshot; exit 0 ;;
esac
check
exit $?
