---
name: design-sketch
description: Write the sketch the owner approves before code, for a new mechanic, data type or piece of shared state, or a change spanning more than one of sim/, server/, net/ and client/. Use before writing any code for such a change.
---

# Design sketch

The rules are in `.claude/rules/design.md`; read it first. This is the shape.

Post the sketch and wait for the owner's OK. Write no code first.

- **What it does**, in a few lines, in the owner's terms.
- **Data:** each piece of state, who owns it, and what's an attribute and
  what's a type.
- **Names** for every new type, file, function and field, checked against
  the naming rules in `.claude/rules/style.md`.
- **Existing code** that does something similar, and how this extends it.
  A fix to a structure that fights the change is its own item.
- **New files:** as `design.md` says to name them. "None" if none.
- **New dependencies:** as `design.md` says to name them, each with why.
  Trace every value the change reads from another folder or that two
  folders must agree on (a number on the wire, a count from
  `shared/data/`) to the script that uses it, and name the existing
  reference it travels through. For any new line in
  `game/tests/dependencies.txt`, give the line and why no existing route
  works. "None" only after that trace. A dependency found only once the
  code is written goes back to the owner as a sketch change.
- **Branches**, if the work won't fit one branch (see "Branch size" in
  `.claude/rules/workflow.md`): the layers in order and what each holds,
  groundwork (types, data, interfaces) first, then the behavior that uses
  it.
- **State walk:** list every state the change can be in (each slot empty
  or full, each input mode, each phase, whatever applies), and check each
  written rule and each rule the owner gave against each state. Every
  conflict, and every state no rule covers, becomes an open call. Also
  list existing names the change makes untrue.
- **Open calls for the owner:** every choice the owner hasn't made (values,
  controls, UI, rules, names, where things go), each with its options and
  what each gains and costs, none presented as the obvious one. Under each
  option, name any further call picking it would force, and ask that call
  in the same batch.

Before opening a PR for the sketched work, list for the owner every way
the branch differs from the approved sketch: names, files, dependencies,
behavior, and anything added or dropped. Wait for their OK; a difference
is fine to propose, never to ship unannounced. With no differences, say
so and open the PR.
