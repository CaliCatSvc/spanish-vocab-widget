# Spanish Vocab Widget for macOS

A compact desktop vocabulary strip for macOS 26 or later. It displays Mexican Spanish vocabulary from a CSV file, speaks the Spanish when clicked, advances automatically, and includes back and forward controls.

## Shareware

Spanish Vocab Widget is honor-system shareware. You may evaluate it for 30 days, then purchase a personal license for a one-time payment of $9.99 USD. There is no subscription or automatic renewal. One license covers one person on Macs that person owns or controls.

Purchases are handled through PayPal. See [Shareware Terms](SHAREWARE.md), [Privacy Notice](PRIVACY.md), and [License](LICENSE).

## Features

- Click the Spanish word or phrase to hear it spoken with a Mexican Spanish voice
- Choose among the Mexican Spanish men’s and women’s voices installed on the Mac
- Back and forward arrows with word history
- Automatic changes every 1, 3, 5, 10, or 15 minutes
- Random or grouped-by-theme order
- Fixed 40-point height with an automatically fitted width
- Optional pronunciation display, hidden by default
- Custom font, size, weight, colors, and opacity
- Import a CSV from the menu
- Update downloads, installs, and reopens the latest matching edition, or confirms that the app is current
- Vocabulary is stored separately from the app, so updates do not replace it
- Includes 100 practical Mexican Spanish starter words and phrases
- Standalone on macOS 26 or later, with no additional software required

## Install

1. Download the latest ZIP from Releases.
2. Open the ZIP.
3. Double-click `Install Spanish Vocab Widget.command`.
4. If macOS asks, approve opening the installer.

The app is installed in your personal Applications folder and opens automatically.
If an older version is installed there, the installer quits and replaces that app while preserving the separate vocabulary file and settings.

## Your vocabulary CSV

Use the menu bar book icon, then choose `Import Vocabulary CSV…`.

The only required columns are:

```csv
Spanish,English
hola,hello
gracias,thank you
```

Optional columns are `Room`, `Category`, `Pronunciation`, and `Notes`.

For complete instructions on creating, finding, reviewing, and importing additional vocabulary, see [Adding More Vocabulary](HELP.md). The same guide is available from the app menu under `Help: Add More Vocabulary…`.

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

The public release contains only generic code and example vocabulary. A personalized local edition can use that same generic code package for updates while preserving its own app identity, vocabulary folder, vocabulary file, and settings. Personalized installers and vocabulary files do not need to be published.

## Source license change

Versions first released under the current proprietary license are source-available for inspection but may not be redistributed or resold. Copies of earlier versions already received under the MIT License remain governed by the MIT License.
