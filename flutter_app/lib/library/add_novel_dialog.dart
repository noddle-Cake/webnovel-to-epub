import 'package:flutter/material.dart';

import '../data/novel_service.dart';
import '../data/site_extractors.dart';
import 'library_store.dart';

class AddNovelDialog extends StatefulWidget {
  const AddNovelDialog({super.key, required this.store, required this.service});
  final LibraryStore store;
  final NovelService service;
  @override
  State<AddNovelDialog> createState() => _AddNovelDialogState();
}

class _AddNovelDialogState extends State<AddNovelDialog> {
  final _url = TextEditingController();
  bool _busy = false;
  String? _error;
  @override
  void dispose() {
    _url.dispose();
    super.dispose();
  }

  Future<void> _add() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final url = _url.text.trim();
      extractorFor(Uri.parse(url));
      final metadata = await widget.service.detect(url);
      if (!mounted) return;
      await widget.store.add(url, metadata);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(
          () => _error = e is ApiException
              ? e.message
              : 'Could not add this novel. Check the URL and try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_busy,
    child: AlertDialog(
      title: const Text('Add a light novel'),
      content: SizedBox(
        width: 440,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Paste a novel page from Royal Road or RoliaScan. Its details will be saved in your library.',
              ),
              const SizedBox(height: 20),
              TextField(
                key: const Key('add-novel-url'),
                controller: _url,
                autofocus: true,
                enabled: !_busy,
                keyboardType: TextInputType.url,
                onSubmitted: (_) {
                  if (!_busy) _add();
                },
                decoration: const InputDecoration(
                  labelText: 'Novel URL',
                  hintText: 'https://roliascan.com/manga/…',
                ),
              ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 16),
                  child: Text(
                    _error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _busy ? null : _add,
          child: _busy
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Add to library'),
        ),
      ],
    ),
  );
}
