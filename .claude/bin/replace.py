"""Text replacement for agents' python heredocs (.claude/rules/workflow.md).

    PYTHONPATH=<checkout>/.claude/bin python3 - <<'EOF'
    from replace import edit
    edit("game/sim/player.gd", "old text", "new text")
    EOF

edit fails loudly instead of leaving the file unchanged when the old text
isn't there, and refuses old text found more than once, since replacing
every copy is rarely what was meant.
"""
import sys


def edit(path, old, new):
    """Replaces old with new in the file at path. Exits with an error, and
    leaves the file as it was, unless old appears in it exactly once."""
    with open(path) as f:
        text = f.read()
    found = text.count(old)
    if found != 1:
        where = "isn't in" if found == 0 else f"is in {found} places in"
        sys.exit(f"replace.edit: the old text {where} {path}, so it was left as it was:\n{old}")
    with open(path, "w") as f:
        f.write(text.replace(old, new))
