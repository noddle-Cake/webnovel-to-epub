# UI design reference

The library navigation, category controls, cover-grid layout, and novel detail
hierarchy are inspired by [Mihon](https://github.com/mihonapp/mihon), an
Apache-2.0 project. Reference screens: Library, HomeScreen navigation, and
MangaScreen. This is an original Flutter implementation; no Mihon Kotlin code,
logos, screenshots, or cover artwork is bundled. The app includes a visible
credit and link in More.

The light-novel UI has Library, Updates, History, Browse, and More destinations.
A local UI library stores metadata, shelves, recently opened novels, display
preferences, and appearance. It does not store chapter contents or reading
progress. Updates and chapter browsing are explicitly reserved for the future
reader. The existing EPUB exporter remains usable from a book or More.

Appearance supports system, light, dark, e-reader light, and e-reader dark.
E-reader appearances use grayscale rendering, black/white surfaces, increased
contrast, and reduced animation. These are visual modes, not device-specific
e-ink refresh controls. All modes will be reusable by the future reader.

First-run libraries and published previews are empty. Do not seed books, use
personal reading selections in examples, or capture an existing user's library
for screenshots. Live smoke checks require an explicitly supplied URL.
