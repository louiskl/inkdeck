# Changelog

## Unreleased

- Automatic UI scaling for high-resolution screens (Paperwhite, Kobo, reMarkable …): layouts are designed for
  600 px and scaled up, so text keeps its size. Override with `"ui_scale"` in `config.json`.

## 0.1.0 – first public preview

- KOReader plugin with pages, grid layout (portrait 2×4 / landscape 4×2), four widget sizes
- D-pad navigation with selection frame, full-screen widget view, touch support
- Widgets: clock, weather (Open-Meteo), calendar (ICS incl. recurring events), news (RSS/Atom), reminders,
  Now Playing via Last.fm, Home Assistant entities, Home Assistant media player, photo frame, countdown, note,
  Spotify (via optional bridge)
- English and German UI, time zones incl. EU/US daylight saving, 12/24 h clock
- Drag-and-drop web editor
- Optional Python bridge for Spotify, with systemd service installer
- PC preview renderer and tests
