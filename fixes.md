# balance fixes

# UI improvements

# fixes

# new stuff
## more cards

# element system
* add weapons that have an element type
* making a hit with an elemental attack applies a status effect to the enemy
* elements is a separate property from attack types like kinetic/energy/plasma

## Fire
* fire attacks give Overheated N, usually only 1
* multiple hits stack
* fully wears off at end of turn
* Overheated N status gives Blazing to the first N dice rolled in the turn
* Blazing dice deal 1 damage to the card they're used in, then Blazing is removed

## Ice
* ice attacks give Subzero N, usually only 1
* multiple hits stack
* fully wears off at end of turn
* Subzero N status forces the first N dice rolls of the turn to be 1s

## Magnetic
* magnetic attacks give Fused N, usually only 1
* multiple hits stack
* fully wears off at end of turn
* Fused N locks the power slots of the first N cards drawn this turn
* putting any die in a locked slot uses the die to unlock the slot back to a normal slot
* slots are only locked until end of turn
* batteries (and similar) drawn aren't locked, instead they gain 1 charge!

## Dark
* dark attacks give Hidden N, usually only 1
* multiple hits stack
* fully wears off at end of turn
* Hidden N prevents the value of the first N dice rolled this turn from being seen

## Water
* water attacks give Rust N
* water attacks usually have no regular damage
* multiple hits stack
* only reduces by 1 at end of turn
* Rust N deals N damage to a random component at end of turn (can't hit CPUs or batteries)