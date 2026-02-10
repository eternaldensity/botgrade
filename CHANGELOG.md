# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/).

## [Unreleased]

### Added
- Convert dead-end empty spaces to scavenge type (#36)
- Label spaces by connection count (#33)
- Quick combat enemy scaling every 5 combats (#23)
- Add back-to-menu navigation to quick combat (#22)
- Remove in_play zone, add per-turn activation limits (#20)
- Implement scrap resource system for destroyed cards (#7)
- Add scavenging system for defeated robots (#1)

### Fixed
- Battery charges not persisting between quick combat fights (#26)
- Investigate shield removal timing (#24)
- Fix card reuse and discard during turn (#17)
- Reset player card state when transitioning between fights (#16)
- Remove destroyed cards from player deck after combat (#9)
- Fix 0/0 HP display and badge overflow on destroyed cards (#8)
- Fix installed cards lost during scavenge confirm (#6)
- Check victory immediately after card activations (#5)
- Clear last_result on cards during turn cleanup (#4)

### Changed
- Split combat_components.ex into card vs layout modules (#31)
- Write project README.md (#30)
- Add plasma lobber and lithium mode weapon cards (#28)
- Clean up phase controls: remove power up text, restyle turn counter (#27)
- Fix overlapping menu/fight badge with enemy status bar (#25)
- Combat clarity: plating vs shields, unified power phase, immediate activation, damage display (#3)
- Combat UI/UX overhaul: component extraction, layout redesign, card redesign, dice UX (#2)
