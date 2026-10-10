import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'data/novel_api.dart';
import 'data/local_novel_service.dart';
import 'library/library_store.dart';
import 'library/library_screen.dart';
import 'theme.dart';

void main() => runApp(const NovelApp());

class NovelApp extends StatefulWidget {
  const NovelApp({super.key, this.service, this.store});
  final NovelService? service;
  final LibraryStore? store;
  @override
  State<NovelApp> createState() => _NovelAppState();
}

class _NovelAppState extends State<NovelApp> {
  late final NovelService _service;
  LibraryStore? _store;
  String? _loadError;
  @override
  void initState() {
    super.initState();
    _service = widget.service ?? (kIsWeb ? NovelApi() : LocalNovelService());
    _store = widget.store;
    if (_store == null) _load();
  }

  Future<void> _load() async {
    setState(() => _loadError = null);
    try {
      final store = await LibraryStore.load();
      if (mounted) {
        setState(() => _store = store);
      } else {
        store.dispose();
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => _loadError =
              'Your saved library could not be loaded. Please try again.',
        );
      }
    }
  }

  @override
  void dispose() {
    if (widget.service == null) _service.close();
    if (widget.store == null) _store?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final store = _store;
    if (store == null) {
      return MaterialApp(
        theme: novelTheme(Brightness.light),
        home: Scaffold(
          body: Center(
            child: _loadError == null
                ? const CircularProgressIndicator()
                : Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(_loadError!),
                        const SizedBox(height: 16),
                        FilledButton(
                          onPressed: _load,
                          child: const Text('Retry'),
                        ),
                      ],
                    ),
                  ),
          ),
        ),
      );
    }
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        final mode = store.appearance;
        final ereader =
            mode == AppAppearance.ereaderLight ||
            mode == AppAppearance.ereaderDark;
        return MaterialApp(
          title: 'Moonleaf',
          debugShowCheckedModeBanner: false,
          theme: novelTheme(Brightness.light, ereader: ereader),
          darkTheme: novelTheme(Brightness.dark, ereader: ereader),
          themeMode: switch (mode) {
            AppAppearance.system => ThemeMode.system,
            AppAppearance.dark || AppAppearance.ereaderDark => ThemeMode.dark,
            _ => ThemeMode.light,
          },
          themeAnimationDuration: ereader
              ? Duration.zero
              : const Duration(milliseconds: 200),
          builder: (context, child) {
            if (!ereader) return child!;
            return MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(disableAnimations: true, accessibleNavigation: true),
              child: ColorFiltered(
                colorFilter: const ColorFilter.matrix([
                  .2126,
                  .7152,
                  .0722,
                  0,
                  0,
                  .2126,
                  .7152,
                  .0722,
                  0,
                  0,
                  .2126,
                  .7152,
                  .0722,
                  0,
                  0,
                  0,
                  0,
                  0,
                  1,
                  0,
                ]),
                child: child!,
              ),
            );
          },
          home: LibraryScreen(store: store, service: _service),
        );
      },
    );
  }
}
