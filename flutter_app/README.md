# Chapter & Verse

Flutter UI for the Novel to EPUB extraction API, targeting iOS, Android, and web.
See the [repository README](../README.md) for setup, builds, and server configuration.

- `lib/data/novel_api.dart`: API models, request encoding, and readable errors.
- `lib/screens/convert_screen.dart`: metadata, cover selection, job progress, and export.
- `lib/widgets/book_art.dart`: offline book-jacket artwork.
- `lib/theme.dart`: shared colors; `lib/main.dart`: app theme and entry point.
- `test/`: API-client and responsive workflow tests.
- `tool/preview_test.dart`: rendered phone and desktop previews.
