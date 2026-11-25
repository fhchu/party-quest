extends Resource
## One kind of item. Saved player data names it by [member id]; the lobby
## state sends its place in shared/data/items.tres instead.

## How saved player data names it. Never changes once players own it.
@export var id := ""
## What players see it called.
@export var display_name := ""
## Its icon's file name among the client's textures; empty for no icon. Only
## a name: shared/ can't point into client/, and the art is missing from a
## clone, where a texture reference would stop the item loading.
@export var icon_file := ""
