# PhotoSwipe 🗑️

[![Latest release](https://img.shields.io/github/v/release/Fawkward/iosphotoclearner?label=download&style=flat-square)](../../releases/latest)

**Clean up your camera roll the way you swipe on dating apps.** One photo at a time, left to delete, right to keep, up to favorite. Built for people whose Photos library has thousands of screenshots, blurry shots, and duplicates they'll never sort through the normal way.

No account. No subscription. No ads. No data leaves your phone — everything runs locally against your own photo library.

---

## Why you might want this

The stock Photos app makes bulk cleanup tedious: you tap into a photo, tap delete, confirm, go back, repeat. PhotoSwipe turns that into a fast, almost game-like flow:

- **Swipe left** — toss into a trash queue (no confirmation popup each time)
- **Swipe right** — keep and move on
- **Swipe up** — save to a special favorites album so you never lose the important ones
- When you're done, **one tap deletes the whole trash queue at once** (single system confirmation instead of one per photo)

It remembers where you left off, shows you how much space you'll reclaim, and never touches a photo without you deciding.

---

## Features

**Tinder-style triage**
Swipe through your library one item at a time. Big colored overlays show your decision (red = trash, green = keep, blue = favorite) so it's obvious what each swipe does.

**Batch delete**
Deleted photos pile up in a queue shown in the top-right. Hit it once and everything goes to "Recently Deleted" in a single confirmation. iOS keeps them recoverable for 30 days, so a mistake is never permanent.

**Favorites album**
Swipe up and the item is added to an auto-created album called "PhotoSwipe Избранное" (Favorites). The photo stays in your main library — the album just references it, so it costs zero extra storage. Find it later in Photos → Albums.

**Photos and videos, separately**
Two tabs at the bottom. The Photos tab handles still images; the Videos tab autoplays each clip on loop while you decide. Each tab keeps its own progress, trash queue, and counters — they never mix.

**Picks up where you left off**
Your progress is saved between launches. Close the app after reviewing 300 photos, reopen it, and you continue from photo 301 — not from the start. A "Start over" button resets this whenever you want.

**Grid jump**
Tap the grid icon to see all remaining items as thumbnails, then tap any one to start swiping from there. Videos show their duration; queued-for-deletion items are marked.

**Storage awareness**
Every card shows the file's date and size. The header shows a running total of how much space you'll free by emptying the current trash queue, and the finish screen tells you how much you actually reclaimed.

**Undo**
Swiped the wrong way? The undo button steps back one decision and restores it.

---

## How it's built (and why that matters to you)

This repo is set up so **anyone can build the app and install it on their own iPhone for free** — no Mac required, no paid Apple Developer account ($99/yr) needed.

- **Built in the cloud.** A GitHub Actions workflow compiles the app on a macOS runner every time the code changes and produces an unsigned `.ipa`. You don't need Xcode or even a Mac.
- **Installed via AltStore.** AltStore signs the app with your own free Apple ID right on your device. Apps installed this way work for 7 days, then AltStore re-signs them automatically.

It's a SwiftUI app targeting iOS 16+. The whole thing is three Swift files plus the project config — small enough to read in one sitting.

---

## Install it on your iPhone

iOS only runs apps signed for your specific device, so whichever option you pick, the app gets signed with **your own free Apple ID** via AltStore or Sideloadly. No paid Apple Developer account needed. (Apps signed this way run for 7 days, then AltStore re-signs them automatically.)

You'll need [AltStore](https://altstore.io) (or [Sideloadly](https://sideloadly.io)) set up on your phone first — their sites have short guides.

### Option 1 — Just download (recommended)

1. Go to the [**Releases**](../../releases/latest) page and download the latest `PhotoSwipe-vX.X.ipa`.
2. Get it onto your phone (AirDrop, iCloud Drive, or any cloud app).
3. Open it with **AltStore** → it signs with your Apple ID and installs.
4. Trust your Apple ID: Settings → General → VPN & Device Management.
5. On iOS 16+: enable Settings → Privacy & Security → Developer Mode.

That's it — no building anything, no GitHub account needed.

### Option 2 — Build it yourself in the cloud

If there's no release yet, or you changed the code:

1. **Fork** this repo to your own GitHub account.
2. Go to the **Actions** tab — a build starts automatically. Wait ~5 minutes for the green checkmark.
3. Open the finished run, scroll to **Artifacts**, download `PhotoSwipe-ipa`, and unzip to get the `.ipa`.
4. Install it via AltStore exactly like steps 3–6 above.

> First launch asks for photo-library permission. Swiping up the first time may also ask permission to add to albums — both are required for the app to work.

---

## Is it safe?

- **Nothing leaves your device.** There's no network code, no analytics, no server. The app only reads and modifies your local photo library through Apple's official Photos framework.
- **Deletions are reversible.** Trashed photos go to "Recently Deleted" and sit there for 30 days.
- **It's all here.** Every line of source is in this repo. Read it before you build it.

---

## Tech stack

- SwiftUI + Photos (PhotoKit) framework
- iOS 16.0+
- No third-party dependencies
- CI: GitHub Actions (macOS runner, unsigned release build)

## Project layout

```
PhotoSwipe/
├── .github/workflows/build.yml      # Cloud build → unsigned .ipa
├── PhotoSwipe.xcodeproj/            # Xcode project
└── PhotoSwipe/
    ├── PhotoSwipeApp.swift          # Entry point + tab bar
    ├── ContentView.swift            # Swipe UI, cards, grid, video player
    ├── PhotoLibraryManager.swift    # PhotoKit logic, persistence, albums
    ├── Assets.xcassets/             # App icon
    └── Info.plist                   # Permissions
```

## License

MIT — do whatever you want with it. If you build something cool on top, a link back is appreciated but not required.

---

*Not affiliated with Apple. "PhotoSwipe" here refers to this app, unrelated to other projects of the same name.*
