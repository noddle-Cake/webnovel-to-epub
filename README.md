# Moonleaf

Convert supported web novels to EPUB while preserving chapter formatting.
Currently supports Royal Road and RoliaScan text novels.

For RoliaScan, paste the landing-page URL of a novel you choose.
The extractor reads the first-chapter button and follows explicit next links;
the dynamically loaded chapter list is not needed. Image-only manga and pages
without accessible novel text raise an error.

## Download for Android

[![Download Android APK](https://img.shields.io/badge/Download-Android_APK-193E36?logo=android&logoColor=white)](https://github.com/noddle-Cake/webnovel-to-epub/releases/latest/download/chapter-and-verse.apk)

**[Download the latest APK](https://github.com/noddle-Cake/webnovel-to-epub/releases/latest/download/chapter-and-verse.apk)** · [All releases and checksums](https://github.com/noddle-Cake/webnovel-to-epub/releases)

Install the APK on your Android phone and open it. **No server or Python
installation is needed.** The app fetches novels and creates EPUBs on your
phone. Internet is needed to fetch chapters; saved EPUBs can be read offline.
Android may ask you to allow installation from your browser. These are debug
builds; uninstall the previous build if Android rejects an update because
build machines use different debug signing keys.

Merges affecting the app automatically build and publish a universal
debug APK. The download link always points to the latest release, and a
SHA-256 checksum accompanies each APK. The **Android APK** workflow can also
be run manually from GitHub Actions on `master`.

## Light-novel library UI

The Flutter app uses a Mihon-inspired library layout with cover grids or lists,
search, sorting, and **Plan to read / Reading / Completed** shelves. Add a novel
from **Browse → Add novel URL**, open its details, and choose **Create EPUB**.
**More → Create an EPUB** also opens the standalone export tool.

Library metadata, shelves, recently opened novels, and appearance preferences
are saved locally. History records opened detail pages, not chapter reading.
The chapter list, update checking, and in-app reader are planned for the next
phase; their screens clearly indicate this. No sample books are installed.

Choose **Appearance** in the toolbar or More to select **Follow system**,
**Light**, **Dark**, **E-reader light**, or **E-reader dark**. E-reader modes
provide grayscale visuals, black/white surfaces, stronger contrast, and reduced
motion. They do not control hardware e-ink refresh behavior.

Phone navigation becomes a side rail on desktop. The design reference and
scope are documented in [flutter_app/DESIGN.md](flutter_app/DESIGN.md).

## Run the standalone app

Install Flutter 3.47.7 or newer, then:

```sh
cd flutter_app
flutter pub get
flutter run -d macos       # on macOS
flutter run -d windows     # on Windows
flutter run -d linux       # on Linux
flutter devices
flutter run -d DEVICE_ID   # Android or iOS device / simulator
```

Native apps extract directly on the device. Paste a novel homepage, find its
details, edit the title/author/starting chapter, optionally choose a JPEG or
PNG cover, and create an EPUB. Save the finished book using the native file
dialog. Keep the app open while extracting and save before closing or starting
another book: jobs and unsaved EPUBs are held in memory, with one extraction
at a time. Cancellation discards the result after the current request returns.

Desktop builds require the platform's Flutter build tools. Android needs the
Android SDK; iOS and macOS need Xcode. Build on the corresponding host:

```sh
flutter build apk --debug
flutter build ios --release
flutter build macos --release
flutter build windows --release
flutter build linux --release
```

iOS installation on physical devices requires your own Apple signing setup.
Configure application identifiers and release signing before app-store
publication. The downloadable Android package is a development/debug build.

## Optional web client

Browsers restrict requests to novel websites, so the web client uses the
Python API. Native phone and desktop apps do not use this API.

With Python 3.10+ installed, run from the repository root:

```sh
python -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
uvicorn api.main:app --host 127.0.0.1 --port 8000
```

In a second terminal:

```sh
cd flutter_app
flutter pub get
flutter run -d chrome
```

For a built web app, run `flutter build web --release`, then start/restart the
API and open `http://localhost:8000`. It serves `flutter_app/build/web/`.
Hosted web defaults to the same origin for its API; localhost defaults to
`http://localhost:8000`. The web app's **Server connection** button changes
that address. To host the app and API separately, build with
`--dart-define=API_BASE_URL=https://your-api.example` and set
`CORS_ORIGINS=https://your-web-app.example` on the API. `WEB_BUILD_DIR` overrides
the static web directory. API documentation is at `/docs`.

The API keeps jobs in memory: run one worker. Two extractions run concurrently,
with at most 16 retained/queued jobs; results expire after one hour. Restarting
the API clears jobs. The web UI saves its library metadata in browser storage; server jobs are
separate and temporary. There is no user account system.

## Add a site

For native apps, implement `SiteExtractor` in
`flutter_app/lib/data/site_extractors.dart` and register the exact host in
`extractorFor`. Supply pure `book` and `chapter` parsers, update the novel-boundary
validation, and add fixture tests in `flutter_app/test/`. Fetching, progress,
cancellation, and EPUB packaging are shared and need no site-specific changes.

For the optional Python/web service:

1. Add a module in `extractors/` with a class inheriting `BaseExtractor`.
2. Declare exact supported `hosts`, including `www` if appropriate.
3. Implement `parse_book(soup, url)` and `parse_chapter(soup, url, count)`.
4. Import the class and append it to `EXTRACTORS` in `extractors/registry.py`.
5. Add offline parsing tests with representative HTML, including the final
   chapter and missing content.

`parse_book` returns `BookMetadata` with `title`, `author`, `description`,
`cover_url`, and `chapter_1` (use `None` for unavailable values).
`parse_chapter` returns the shared `models.chapter.Chapter` with a title,
HTML body, and `next_url=None` at the end. Raise `ExtractionError` when the
expected content is missing; do not silently export an empty or blocked page.

Use `self.link(url, href)` to resolve relative links. Select the reading body
and explicit next-chapter navigation, rather than relying on button counts or
URL title guesses. Parsing methods do not fetch pages, so they are easy to test.
The base class handles HTTP status checks, a 30-second timeout, and a reusable
session. A custom session can be injected with `Extractor(session=...)`.

`ExtractionService` checks chapter hosts and detects repeated URLs to prevent
navigation loops. `EpubBuilder` uses numbered chapter filenames so repeated
or path-like titles do not collide.

## Test

```sh
pip install -r requirements-dev.txt
python -m pytest tests -q
cd flutter_app
flutter analyze
flutter test
```

Generate phone and desktop screenshots using Flutter's renderer:

```sh
cd flutter_app
flutter test tool/preview_test.dart --update-goldens
```

Previews are saved in `flutter_app/screenshots/`. Bundled DM Sans and Fraunces
fonts use the SIL Open Font License; their licenses are included alongside
font assets.

## Android download automation

Pull requests run Flutter analysis, tests, an Android debug build, and native
Windows/Linux release builds. Desktop bundles are available as workflow
artifacts for 14 days (download the entire bundle). Pushes
to `master` run the same checks and publish the APK and its SHA-256 checksum to
GitHub Releases. Workflow actions and the Flutter SDK are pinned. Pull-request
APKs are also available as workflow artifacts for 14 days.

These are development/debug APKs, not app-store releases. No custom signing
secrets are required. Debug signing keys differ across runners, so updating an
installed APK may require uninstalling its previous version. Production
signing with a stable private key can be configured separately.

Builds use the workflow run number as Android's version code. Native builds
contain the Dart extractors and EPUB writer; no backend address is configured.
