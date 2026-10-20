---
name: refactor-check
description: Before reporting finished work, check the code you just changed for logic that already exists elsewhere in the repository, and extract it when this is the second copy. Use when the flintlock Stop hook asks for a refactor check, or when the user asks to look for duplication in recent changes.
---

# Refactor check

Rule: refactor when the same logic appears a second time. Not the first time (nothing to share yet),
and not later (by the third copy it has already drifted).

## Steps

1. **List what changed.** Start from the changed files the hook gave you, or run `git status` and
   `git diff HEAD`. For each file, note the functions, methods and non-trivial blocks you added or
   rewrote. Skip renames, formatting, imports and one-line glue.

2. **Search for the same logic.** For each of those functions and blocks, search the repository:
   - grep for distinctive identifiers, literals, formulas and call sequences from the block;
   - use symbol search (go-to-definition, references) when available;
   - look at sibling files that do the same kind of job: other views, handlers, commands, tests
     of the same module.
   You are looking for the same steps, not the same text. Renamed variables and reordered
   independent lines still count.

3. **Decide.**
   - Same logic exists once elsewhere (yours is the second copy): extract it into one shared
     function, type or constant next to the code that owns the concept, and call it from both
     places.
   - Only similar, or the two copies are expected to diverge: leave it.
   - Already a third copy or more: extract it all the same, and replace every copy you find.

4. **Keep behaviour.** The extraction is a pure refactor: same inputs, same outputs, same side
   effects and the same error handling. Do not fix or change behaviour in the same step. Build the
   project and run the tests that cover the touched code. They must pass as they did before.
   If they fail, fix the extraction or revert it.

5. **Report in one line** in your final answer: what you extracted and where, or, only if you
   changed nothing, that you searched and found no duplicate. For example:
   - `Refactor check: extracted clamp_to_range() from orders.py and invoices.py into money.py.`
   - `Refactor check: searched for duplicates of the new parsing code, found none.`
