extends Resource
## What every dummy attack has, in seconds. A kind's attacks are its fire
## and its charge.
##
## Every value is PLACEHOLDER (design).

## How long before the attack the dummy locks onto where its target is.
@export var aim_lock_sec := 0.0
## How likely a random choice is to pick it, against the other attacks it
## could pick: weights 3 and 1 are 75% and 25%. When every weight is 0,
## each is as likely as the others.
@export var weight := 1.0
