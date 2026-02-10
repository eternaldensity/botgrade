# balance fixes

* ~~strikebolt cpu ability to require strikebolt cell in hand~~ (requires_card_name field on cpu_ability, validated in activate_cpu_by_type + AI)
* ~~prevent reuse of items via activations per turn (usually 1)~~ (all card types use activated_this_turn flag, in_play zone removed)
* ~~prevent discard of cards that have been used this turn~~ (blocked in toggle_cpu_discard + AI logic)
* ~~number of active CPUs limited by number of batteries. (if you have 3 batteries and 5 CPUs the newest 2 can't be activated)~~ (cpu_has_power? checks battery count vs CPU position in installed list)

# UI improvements
* ~~animate the enemy's turn, showing damage as it's dealt to your components like it does for their damge to yours~~ (enemy turn broken into step-by-step timed broadcasts via Process.send_after in CombatServer)
* ~~i don't think there's any need for a separate in-play area~~
* ~~some cards don't fully display what they do~~ (card_stats shows damage formulas, slot conditions, dual_mode info, CPU ability descriptions)
* ~~it's hard to tell what salvaged cards will do~~ (scavenge panel uses card_detail_stats with damage penalty warnings and card HP)
* display the shield and plating levels of opponent like for the player
* ~~make saves deletable~~ (delete button on home page with POST route and confirm dialog)

# fixes

## ~~some damaged items have no effect on damage~~
* ~~strikebolt cell shows 1d6 being replaced with 1d6~~ (1-die batteries now cap die value at die_sides-2 instead of losing a die)
* ~~damaged CPU should fail its ability 1/3 of the time~~ (1/3 chance to malfunction, consumes activation)

## campaign is stuck after finishing the lab

# new stuff
## more cards
* add beam splitter utility card: cut a die into two
* add a kinetic laser weapon which needs a 3 die or less, and deals 1 damage, can activate 3 time per turn
* add an overcharge utility card: spend a die 3 or greater: your attacks deal +1 damage this turn
* new plasma weapon that deals 2x the die value and 1 to itself
* cpu that gives a utility card an extra activation this turn
* new energy weapon that gets +1 damage each weapon activation this turn
* kinetic weapon: boxing glove. requires a 2+ die and does die -2 damage, has 2 activations per turn

## element system
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