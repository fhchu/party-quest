#!/usr/bin/env bash
# Runs every GdUnit4 suite in tests/ headless. Exit code 0 means all passed.
# Pass a path to run less, e.g. ./run-tests.sh res://tests/sim
cd "$(dirname "$0")"
godot="${GODOT_BIN:-godot}"
# Newly added scripts aren't known to the project until it's imported.
"$godot" --headless --import > /dev/null 2>&1
# --remote-debug to an unused port keeps Godot's debugger from waiting for
# input on a script error. GdUnit4 v6 refuses to run headless unless told
# to (--ignoreHeadlessMode); none of these tests draw anything.
"$godot" --headless --path . -s -d --remote-debug tcp://127.0.0.1:0 \
	res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -c -a "${1:-res://tests}"
