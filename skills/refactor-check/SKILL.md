---
name: refactor-check
description: Before reporting finished work, check the code you just changed for logic that already exists elsewhere in the repository, and extract it when this is the second copy; put members you added or whose modifiers you changed where the type's member order says they belong; suggest (never apply) structural fixes. Use when the flintlock Stop hook asks for a refactor check, or when the user asks to look for duplication or misplaced members in recent changes.
---

# Refactor check

Rule: refactor when the same logic appears a second time. Not the first time (nothing to share yet),
and not later (by the third copy it has already drifted).

## Steps

1. **List what changed.** Start from the changed files the hook gave you, or run `git status` and
   `git diff HEAD`. For each file, note the functions, methods and non-trivial blocks you added or
   rewrote. Skip renames, formatting, imports and one-line glue. Also note every member (field,
   property, constructor, method, nested type) that you added, and every existing member whose
   access modifier, `static`/`const`/companion placement or kind you changed. Step 5 needs them.

2. **Search for the same logic.** For each of those functions and blocks, search the repository:
   - grep for distinctive identifiers, literals, formulas and call sequences from the block;
   - use symbol search (go-to-definition, references) when available;
   - look at sibling files that do the same kind of job: other views, handlers, commands, tests
     of the same module.
   You are looking for the same steps, not the same text. Renamed variables and reordered
   independent lines still count.

3. **Decide.**
   - The logic already exists as a function, type or constant you can call: replace your copy with
     a call to it. Do not create a new one next to it, and do not wrap it in a function that only
     forwards to it.
   - It almost matches an existing function but not quite: do not bend that function to fit, such
     as by adding a boolean or mode parameter. Leave both as they are, or suggest a change in step 6.
   - Same logic exists once elsewhere (yours is the second copy): extract it into one shared
     function, type or constant next to the code that owns the concept, and call it from both
     places.
   - Only similar, or the two copies are expected to diverge: leave it.
   - Already a third copy or more: extract it all the same, and replace every copy you find.

4. **Keep behaviour.** The extraction is a pure refactor: same inputs, same outputs, same side
   effects and the same error handling. Do not fix or change behaviour in the same step. Build the
   project and run the tests that cover the touched code. They must pass as they did before.
   If they fail, fix the extraction or revert it.

5. **Check member placement.** For each member noted in step 1, find where it belongs in its type
   and move it there if it is elsewhere. A member appended at the end of the type, or a member
   whose modifier changed while it stayed in its old section, is the usual case.

   Which order applies, first match wins:
   1. The project's linter configuration for member order (StyleCop, Checkstyle, detekt, ktlint,
      `.editorconfig`), or an order written in the project's instructions (CLAUDE.md, AGENTS.md,
      contributing guide).
   2. The order the type itself already follows, when it clearly follows one that differs from the
      language default below. Stay consistent with the file.
   3. The language default:
      - **C#** (StyleCop SA1201-SA1204): by kind: fields, constructors, finalizers, delegates,
        events, enums, interfaces, properties, indexers, methods, nested structs, nested classes.
        Within a kind, by access: `public`, `internal`, `protected internal`, `protected`,
        `private protected`, `private`. Then `const` before other fields, `static` before
        instance members.
      - **Java** (Checkstyle DeclarationOrder): static fields, then instance fields, each ordered
        `public`, `protected`, package-private, `private`; then constructors; then methods.
        Methods are not ordered by access: put a new method next to the methods it works with
        (its caller or its closest relatives), never at the end by default. Keep overloads
        together.
      - **Kotlin** (Kotlin coding conventions, class layout): properties and `init` blocks,
        secondary constructors, functions, then the companion object last. Do not order by
        visibility: a changed modifier alone is no reason to move a member. Put a new function
        next to related code, keep overloads together, and keep the members of an implemented
        interface in the interface's order.
      - **TypeScript** (typescript-eslint `member-ordering` default): index and call signatures,
        fields, static blocks, constructors, accessors, getters, setters, methods. Within a kind:
        `static`, then decorated, then instance, then `abstract`; within each of those, `public`,
        `protected`, `private`, then `#private`. Keep a getter and its setter together when the
        file already does.
      - **JavaScript**: no common standard. Follow the class's existing order; if it has none,
        leave placement alone.
      - **Top-level declarations** (exported and local functions, constants) in any language:
        the file's existing order. If it has none, leave placement alone.
      - **Other languages**: the type's existing order. If it has none, leave placement alone.

   Limits:
   - Move only the members from step 1. Do not reorder the rest of the type: that is a separate
     decision for the user (step 6 may suggest it).
   - Moving a member changes no behaviour. In languages where declaration order does matter
     (field initializers that read other fields, Kotlin properties read by `init` blocks,
     C# static field initializers), keep the order that keeps behaviour, and say why in the report.
   - Moving an existing member makes its diff look like a deletion and an addition, which hides
     the modifier change inside it. Name every moved existing member and its modifier change in
     the report (step 7), so the reviewer does not have to find it in the diff.

6. **Note structure, do not change it.** While reading the changed code, you may notice a
   structural problem it created or made worse. Examples: a function that now does two separate jobs,
   a parameter list or nesting that keeps growing, code that your change left unused, or logic placed
   in a module that does not own the concept. Do not fix these here. A structural change is a
   decision for the user, and it belongs in its own diff. Suggest at most two, and only problems
   you can point to in the changed code. Skip this step if nothing stands out.

7. **Report** in your final answer:
   - One line: what you extracted and where, or, only if you changed nothing, that you searched
     and found no duplicate.
   - One line per existing member you moved in step 5: the member, its modifier change and the
     section it moved to. New members you placed need no line.
   - Optionally, one line per structural suggestion from step 6: what, where and why.

   For example:
   - `Refactor check: extracted clamp_to_range() from orders.py and invoices.py into money.py.`
   - `Refactor check: searched for duplicates of the new parsing code, found none.`
   - `Moved: OrderService.Load() private -> public, into the public methods of OrderService.cs.`
   - `Suggestion: load_config() in app.py now parses and validates; split validate_config() out.`
