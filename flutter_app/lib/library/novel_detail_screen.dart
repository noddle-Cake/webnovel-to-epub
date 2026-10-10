import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'library_store.dart';
import 'novel_cover.dart';

Future<void> openSource(BuildContext context, String url) async {
  try {
    if (!await launchUrl(
      Uri.parse(url),
      mode: LaunchMode.externalApplication,
    )) {
      throw StateError('Cannot open link');
    }
  } catch (_) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not open the source in your browser.'),
        ),
      );
    }
  }
}

class NovelDetailScreen extends StatelessWidget {
  const NovelDetailScreen({
    super.key,
    required this.url,
    required this.store,
    required this.onExport,
  });
  final String url;
  final LibraryStore store;
  final void Function(LibraryNovel) onExport;
  Future<void> _shelf(BuildContext context, LibraryNovel novel) async {
    final shelf = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                'Move to shelf',
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
            ...shelves.map(
              (s) => ListTile(
                title: Text(s),
                trailing: s == novel.shelf
                    ? const Icon(Icons.check_rounded)
                    : null,
                onTap: () => Navigator.pop(context, s),
              ),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
    if (shelf == null) return;
    try {
      await store.setShelf(url, shelf);
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not save the shelf change.')),
        );
      }
    }
  }

  Future<void> _remove(BuildContext context) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove from library?'),
        content: const Text(
          'This removes the saved details and history. EPUB files you have exported will stay on your device.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    try {
      await store.remove(url);
      if (context.mounted) Navigator.pop(context);
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not remove this novel.')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: store,
    builder: (context, _) {
      final novel = store.novels.where((n) => n.url == url).firstOrNull;
      if (novel == null) return const Scaffold(body: SizedBox.shrink());
      final colors = Theme.of(context).colorScheme;
      return Scaffold(
        appBar: AppBar(
          title: const Text('Novel details'),
          actions: [
            IconButton(
              tooltip: 'Open source website',
              icon: const Icon(Icons.open_in_new),
              onPressed: () => openSource(context, url),
            ),
            PopupMenuButton<String>(
              onSelected: (_) => _remove(context),
              itemBuilder: (_) => [
                const PopupMenuItem(
                  value: 'remove',
                  child: Text('Remove from library'),
                ),
              ],
            ),
          ],
        ),
        body: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 900),
            child: ListView(
              padding: const EdgeInsets.all(24),
              children: [
                LayoutBuilder(
                  builder: (context, constraints) {
                    final stacked =
                        constraints.maxWidth < 320 ||
                        MediaQuery.textScalerOf(context).scale(1) > 1.25;
                    final cover = SizedBox(
                      width: stacked
                          ? 130
                          : constraints.maxWidth < 400
                          ? 108
                          : 160,
                      height: stacked
                          ? 195
                          : constraints.maxWidth < 400
                          ? 162
                          : 240,
                      child: NovelCover(novel: novel),
                    );
                    final details = Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          novel.title,
                          style: Theme.of(context).textTheme.headlineSmall
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 14),
                        Text(
                          novel.author.isEmpty
                              ? 'Unknown author'
                              : novel.author,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '${novel.source} · Light novel',
                          style: TextStyle(color: colors.onSurfaceVariant),
                        ),
                        const SizedBox(height: 16),
                        ActionChip(
                          avatar: const Icon(
                            Icons.collections_bookmark_outlined,
                            size: 18,
                          ),
                          label: Text(novel.shelf),
                          onPressed: () => _shelf(context, novel),
                        ),
                      ],
                    );
                    return stacked
                        ? Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              cover,
                              const SizedBox(height: 24),
                              details,
                            ],
                          )
                        : Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              cover,
                              const SizedBox(width: 24),
                              Expanded(child: details),
                            ],
                          );
                  },
                ),
                const SizedBox(height: 28),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    FilledButton.icon(
                      onPressed: () => onExport(novel),
                      icon: const Icon(Icons.file_download_outlined),
                      label: const Text('Create EPUB'),
                    ),
                    OutlinedButton.icon(
                      onPressed: () => _shelf(context, novel),
                      icon: const Icon(Icons.folder_outlined),
                      label: const Text('Change shelf'),
                    ),
                  ],
                ),
                const SizedBox(height: 32),
                Text('Synopsis', style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 12),
                SelectableText(
                  novel.description?.isNotEmpty == true
                      ? novel.description!
                      : 'No synopsis was provided by this source.',
                  style: TextStyle(
                    height: 1.65,
                    color: colors.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 32),
                const Divider(),
                const SizedBox(height: 20),
                Text('Chapters', style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 16),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          Icons.chrome_reader_mode_outlined,
                          color: colors.primary,
                          size: 28,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'A home for your next chapter',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'The in-app reader and chapter list are coming next. For now, create an EPUB to read in your favorite reading app.',
                          style: TextStyle(height: 1.5),
                        ),
                        if (novel.firstChapter.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 16),
                            child: TextButton.icon(
                              onPressed: () =>
                                  openSource(context, novel.firstChapter),
                              icon: const Icon(Icons.open_in_new, size: 18),
                              label: const Text(
                                'First chapter on source website',
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 32),
              ],
            ),
          ),
        ),
      );
    },
  );
}
