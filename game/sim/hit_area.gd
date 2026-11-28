extends RefCounted
## What an action hits with while it's busy: convex pieces placed relative
## to its holder, which the world turns with the holder's facing. It hits
## each unit once. The world drops it once its action is idle or gone.

## The pieces, in the holder's frame: +x is its facing.
var pieces: Array[ConvexPolygonShape2D] = []
## Where the pieces are relative to the holder; its action moves it.
var local := Transform2D.IDENTITY
## The units it has hit, by ID.
var struck_ids: Array[int] = []
## The player it follows. Weak, like [member action].
var holder: WeakRef
## The action that made it, until that action ends it: then null. Weak,
## since the action keeps it to move it: a cycle of references is never
## freed.
var action: WeakRef
