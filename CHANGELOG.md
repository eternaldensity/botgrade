# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/).

## [Unreleased]

### Added
- Implement scrap resource system for destroyed cards (#7)
- Add scavenging system for defeated robots (#1)

### Fixed
- Reset player card state when transitioning between fights (#16)
- Remove destroyed cards from player deck after combat (#9)
- Fix 0/0 HP display and badge overflow on destroyed cards (#8)
- Fix installed cards lost during scavenge confirm (#6)
- Check victory immediately after card activations (#5)
- Clear last_result on cards during turn cleanup (#4)

### Changed
- Combat clarity: plating vs shields, unified power phase, immediate activation, damage display (#3)
- Combat UI/UX overhaul: component extraction, layout redesign, card redesign, dice UX (#2)
