# Light Novel Extractor

Convert supported web novels to EPUB while preserving chapter formatting.
Currently supports Royal Road and RoliaScan text novels.

For RoliaScan, paste the novel landing page, for example:
`https://roliascan.com/manga/the-regressor-and-the-blind-saint-novel/`.
The extractor reads the first-chapter button and follows explicit next links;
the dynamically loaded chapter list is not needed. Image-only manga and pages
without accessible novel text raise an error.

## Run the API

Python 3.10+ and Flutter 3.47+ are required. The old Streamlit and NiceGUI
interfaces have been replaced by the Flutter app in `flutter_app/`.

```sh
python -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
uvicorn api.main:app --host 0.0.0.0 --port 8000
```

The API retains the existing extraction service and site parsers. It exposes
metadata detection, background extraction, chapter progress, cancellation,
and EPUB downloads. API documentation: `http://localhost:8000/docs`.

## Run Flutter

In a second terminal:

```sh
cd flutter_app
flutter pub get
flutter run -d chrome
```

The interface, **Chapter & Verse**, adapts to phone and desktop screens. Paste
a novel homepage, find its details, edit the title/author/starting chapter,
optionally upload a JPEG or PNG cover, and create an EPUB. Progress shows the
number of chapters collected. Save the finished book with the browser download
or the native file dialog on iOS and Android.

For a mobile simulator/emulator, choose its device ID from `flutter devices`:

```sh
flutter run -d DEVICE_ID
```

Local defaults are `http://localhost:8000` for web and the iOS simulator, and
`http://10.0.2.2:8000` for the Android emulator. For physical phones, use the
computer's local network address through the connection settings button, or
configure it at launch:

```sh
flutter run -d DEVICE_ID --dart-define=API_BASE_URL=http://192.168.1.10:8000
```

The phone and server must be on the same network. Local HTTP is enabled in
Android debug builds; use an HTTPS API for mobile release builds.

## Build

```sh
cd flutter_app
flutter build web --release
flutter build apk --release --dart-define=API_BASE_URL=https://your-api.example
flutter build ios --release --dart-define=API_BASE_URL=https://your-api.example
```

Android builds need the Android SDK and accepted licenses. iOS builds need
Xcode and your signing configuration. Set your own application identifier and
release signing before publishing to app stores; generated Android release
configuration currently uses the development signing key.

After building web, start/restart the API: it serves `flutter_app/build/web/`
at `http://localhost:8000`. Hosted web defaults to the same origin for its API.
To host the app and API separately, build with `--dart-define=API_BASE_URL=...`
and set `CORS_ORIGINS=https://your-web-app.example` on the API. Localhost web
origins are accepted for development. `WEB_BUILD_DIR` can override the static
web build directory.

Extraction jobs are kept in memory: run one API worker. Two extractions run
concurrently, with at most 16 retained/queued jobs. Results expire one hour
after completion; restarting the API clears jobs. Cancellation stops after
the current page request returns. This is a personal/server-hosted app,
with no persistent library or user accounts.

## Add a site

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
