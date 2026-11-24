extends RefCounted
## Names engine classes the web export needs but the editor's build profile
## detection can't find, so a regenerated deploy/web-template/*.gdbuild
## keeps them. Never loaded: detection only reads the names in it.

## GDScript: detection records the classes a script's code names, never the
## script's own class, so no other file marks it as used.
var kept_gdscript: GDScript
