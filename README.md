# Spanish Vocab Widget for macOS

A compact desktop vocabulary strip for macOS 26 or later. It displays Mexican Spanish vocabulary from a CSV file, speaks the Spanish when clicked, advances automatically, and includes back and forward controls.

## Features

- Click the Spanish word or phrase to hear it spoken with a Mexican Spanish voice
- Back and forward arrows with word history
- Automatic changes every 1, 3, 5, 10, or 15 minutes
- Random or grouped-by-theme order
- Fixed 40-point height with an automatically fitted width
- Optional pronunciation display, hidden by default
- Custom font, size, weight, colors, and opacity
- Import a CSV from the menu
- Check for Updates opens the latest GitHub release
- Vocabulary is stored separately from the app, so updates do not replace it

## Install

1. Download the latest ZIP from Releases.
2. Open the ZIP.
3. Double-click `Install Spanish Vocab Widget.command`.
4. If macOS asks, approve opening the installer.

The app is installed in your personal Applications folder and opens automatically.

## Your vocabulary CSV

Use the menu bar book icon, then choose `Import Vocabulary CSV…`.

The only required columns are:

```csv
Spanish,English
hola,hello
gracias,thank you
```

Optional columns are `Room`, `Category`, `Pronunciation`, and `Notes`.

Your active vocabulary file is stored at:

`~/Documents/Spanish Vocab Widget/Vocabulary.csv`

Installing an app update does not overwrite this file.

## Build from source

Run:

```bash
./scripts/build.sh
./scripts/package.sh
```

The app and release ZIP are placed in `dist`.

## Privacy

The app works locally. It does not upload vocabulary or usage data.
