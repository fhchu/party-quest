---
name: design-sketch
description: Write the sketch the owner approves before code, for a new mechanic, data type or piece of shared state, or a change spanning more than one of sim/, server/, net/ and client/. Use before writing any code for such a change.
---

# Design sketch

The rules are in `.claude/rules/design.md`; read it first. This is the shape.

Post the sketch and wait for the owner's OK. Write no code first.

- **What it does**, in a few lines, in the owner's terms.
- **Data:** each piece of state, who owns it, and what's an attribute and
  what's a type (behavior comes from attributes).
- **Names** for every new type, file, function and field, checked against
  the naming rules in `.claude/rules/style.md`.
- **Existing code** that does something similar, and how this extends it
  instead of adding a parallel version. If the current structure fights
  the change, say what's in the way and propose the fix as its own item.
- **New files:** each path and why it belongs in that folder. "None" if
  none.
- **New dependencies:** each `preload`, import or call into another script
  the change adds, removes or moves, with the scripts at both ends and why.
  For each reference across game folders, the line it needs in
  `game/tests/dependencies.txt` and an alternative that avoids it. "None"
  if none.
- **Branches**, if the work won't fit one branch: the layers in order and
  what each holds (see the `stacked-prs` skill).
- **Open calls for the owner:** every choice the owner hasn't made (values,
  controls, UI, rules, names, where things go), each with its options and
  what each gains and costs, none presented as the obvious one.
