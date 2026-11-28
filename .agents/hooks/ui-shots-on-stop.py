#!/usr/bin/env python3
"""Stop hook for party-quest, in Claude Code and Antigravity alike: a turn
that edited anything on screen can't end until the agent has run
game/ui-gallery.sh after the last such edit and then opened the contact
sheet it writes. The turn's calls come from turn.py's log.

On screen means anything under game/client/ui/, in the main checkout or any
worktree of the repo. Edits made through Bash (sed) aren't seen.
Skips quietly while the repo has no ui-gallery.sh. Blocks once per stop: if
the agent tries to stop again with the check still unmet, the turn ends and
the owner is told instead, so a broken gallery can't trap the agent in a
loop.
"""
import os
import subprocess
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import turn  # noqa: E402  (found through the line above)

# Where ui-gallery.sh writes the contact sheet, in whichever checkout ran it.
SHEET = "game/build/ui_gallery/contact_sheet.png"
GALLERY = "ui-gallery.sh"


def git_out(folder, *args):
    """git's output in folder, stripped; "" when it fails."""
    out = subprocess.run(["git", "-C", folder, *args], capture_output=True, text=True)
    return out.stdout.strip() if out.returncode == 0 else ""


def in_repo_path(path, project):
    """path from its checkout's top, for a file in any checkout of this repo
    (the main one or a worktree, wherever the session itself started);
    None for a file elsewhere."""
    folder = os.path.dirname(os.path.realpath(path))
    if not os.path.isdir(folder):
        return None
    common = "--path-format=absolute", "--git-common-dir"
    if os.path.realpath(git_out(folder, "rev-parse", *common)) \
            != os.path.realpath(git_out(project, "rev-parse", *common)):
        return None
    top = git_out(folder, "rev-parse", "--show-toplevel")
    return os.path.relpath(os.path.realpath(path), os.path.realpath(top))


def on_screen(path, project):
    """True for a file under game/client/ui/."""
    return (in_repo_path(path, project) or "").startswith("game/client/ui/")


def main():
    e = turn.event()
    project = e.project
    if not os.path.exists(os.path.join(project, "game", GALLERY)):
        e.let_stop()
    _, calls = e.turn()

    last_edit = None
    for i, c in enumerate(calls):
        if c["tool"] == "edit" and c["path"] and on_screen(c["path"], project):
            last_edit = i
    if last_edit is None:
        e.let_stop()

    ran = None
    for i in range(last_edit + 1, len(calls)):
        if calls[i]["tool"] == "shell" and GALLERY in calls[i]["command"]:
            ran = i
    opened = ran is not None and any(
        calls[i]["tool"] == "read" and calls[i]["path"]
        and in_repo_path(calls[i]["path"], project) == SHEET
        for i in range(ran + 1, len(calls)))
    if opened:
        e.let_stop()

    missing = ("run game/ui-gallery.sh" if ran is None else "") + \
        (" and then " if ran is None else "") + f"open {SHEET} with your file-reading tool"
    if e.stop_blocked_before():
        e.let_stop(f"The agent changed UI files this turn but didn't {missing.strip()}.")
    e.keep_going(f"You changed on-screen files this turn. Before finishing, {missing.strip()}, "
                 "look at the shots, and fix or report anything that looks wrong "
                 "(.agents/rules/ui.md).")


main()
