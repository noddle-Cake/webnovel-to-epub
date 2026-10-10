import 'package:flutter/material.dart';

import 'library_store.dart';

class NovelCover extends StatelessWidget {
  const NovelCover({super.key, required this.novel, this.overlay = false});
  final LibraryNovel novel;
  final bool overlay;
  @override
  Widget build(BuildContext context) {
    final seed = novel.title.codeUnits.fold(0, (a, b) => a + b);
    const palettes = [
      [Color(0xFF30465D), Color(0xFF121D31)],
      [Color(0xFF745644), Color(0xFF292135)],
      [Color(0xFF52644C), Color(0xFF15292E)],
      [Color(0xFF725571), Color(0xFF282039)],
    ];
    Widget fallback() => LayoutBuilder(
      builder: (context, size) => DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: palettes[seed % palettes.length],
          ),
        ),
        child: Stack(
          fit: StackFit.expand,
          children: [
            Positioned(
              right: -32,
              top: 30,
              child: Icon(
                Icons.auto_stories_rounded,
                size: 170,
                color: Colors.white.withValues(alpha: .07),
              ),
            ),
            Padding(
              padding: EdgeInsets.all(size.maxWidth > 80 ? 12 : 4),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  border: Border.all(
                    color: Colors.white.withValues(alpha: .16),
                  ),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Center(
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.auto_stories_outlined,
                      color: const Color(0xFFE7D8BE),
                      size: size.maxWidth > 80 ? 32 : 20,
                    ),
                    if (!overlay && size.maxHeight > 180) ...[
                      const SizedBox(height: 16),
                      Text(
                        novel.title,
                        maxLines: 4,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontFamily: 'Fraunces',
                          color: Color(0xFFF5E9D1),
                          fontSize: 17,
                          height: 1.2,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (novel.coverUrl?.isNotEmpty ?? false)
            Image.network(
              novel.coverUrl!,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => fallback(),
              loadingBuilder: (_, child, progress) =>
                  progress == null ? child : fallback(),
            )
          else
            fallback(),
          if (overlay) ...[
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment(0, .25),
                  end: Alignment.bottomCenter,
                  colors: [Colors.transparent, Color(0xE6000000)],
                ),
              ),
            ),
            Positioned(
              left: 10,
              right: 10,
              bottom: 12,
              child: Text(
                novel.title,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                  height: 1.2,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
