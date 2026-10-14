# Contributing to InkDeck

Thanks for helping! InkDeck is a small project – issues and pull requests of any size are welcome.

## Most useful right now

- **Testing on real devices.** Tell us your model, firmware and KOReader version, and what worked or didn't
  (a photo helps). Kindle 4/5, Paperwhite, Kobo, PocketBook – all interesting.
- **New widgets** – see [docs/WIDGETS.md](docs/WIDGETS.md). Ideas: transit departures, air quality, package tracking,
  RSS-based comics, sports scores, a habit tracker, a pomodoro timer, chess puzzles.
- **Translations** – add a table to `inkdeck.koplugin/inkdeck/i18n.lua`.
- **3D-printable stands and frames** – put STL files and photos into `hardware/`.

## Ground rules

- Keep the plugin dependency-free: plain Lua that runs on KOReader's LuaJIT. No compiled modules.
- Keep the core usable **without any server**. Server-side helpers go into `bridge/` and stay optional.
- Be gentle with old hardware: few requests, small payloads, timeouts, no busy loops.
- User-visible strings go through `T()` / `F()` with a German translation (the tests check this).

## Before you open a PR

```bash
pip install lupa pillow fonttools
git clone --depth 1 https://github.com/koreader/koreader-fonts
python3 tools/test_util.py
python3 tools/test_glue.py
python3 tools/preview.py --fonts koreader-fonts --out previews   # look at the PNGs
```

CI runs the same commands on every push.

## Reporting bugs

Please include: device + firmware, KOReader version, InkDeck version (Menu → About), your `config.json` without
tokens/API keys, and the relevant lines from `koreader/crash.log`.
