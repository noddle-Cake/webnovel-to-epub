import 'package:flutter/material.dart';

/// A code-drawn book jacket that also works offline, before a cover is detected.
class BookArt extends StatelessWidget {
  const BookArt({
    super.key,
    this.title = 'Your next\ngreat read',
    this.author = 'CHAPTER & VERSE',
  });
  final String title;
  final String author;

  @override
  Widget build(BuildContext context) => AspectRatio(
    aspectRatio: 0.68,
    child: Container(
      decoration: BoxDecoration(
        color: const Color(0xFF224B40),
        borderRadius: BorderRadius.circular(4),
        boxShadow: const [
          BoxShadow(
            color: Color(0x29112D25),
            blurRadius: 25,
            offset: Offset(8, 14),
          ),
        ],
      ),
      child: Stack(
        children: [
          const Positioned.fill(child: CustomPaint(painter: _JacketPainter())),
          Padding(
            padding: const EdgeInsets.fromLTRB(22, 26, 18, 22),
            child: LayoutBuilder(
              builder: (context, constraints) => Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(
                    Icons.auto_stories_outlined,
                    color: Color(0xFFDEC9A1),
                    size: 26,
                  ),
                  const SizedBox(height: 16),
                  Expanded(
                    child: Align(
                      alignment: Alignment.bottomLeft,
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.bottomLeft,
                        child: SizedBox(
                          width: constraints.maxWidth,
                          child: Text(
                            title.isEmpty ? 'Your next\ngreat read' : title,
                            maxLines: 5,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontFamily: 'Fraunces',
                              color: Color(0xFFF5EFE0),
                              fontSize: 25,
                              height: 1.15,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    height: 28,
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.topLeft,
                      child: SizedBox(
                        width: constraints.maxWidth,
                        child: Text(
                          author.isEmpty
                              ? 'CHAPTER & VERSE'
                              : author.toUpperCase(),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 9,
                            letterSpacing: 1.8,
                            color: Color(0xFFDEC9A1),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

class _JacketPainter extends CustomPainter {
  const _JacketPainter();
  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    final paint = Paint()
      ..color = const Color(0xFF7B9E82).withValues(alpha: 0.4)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    for (var i = 0; i < 7; i++) {
      canvas.drawCircle(
        Offset(size.width * .9, size.height * .2),
        size.width * (.22 + i * .08),
        paint,
      );
    }
    canvas.drawLine(
      const Offset(8, 0),
      Offset(8, size.height),
      Paint()
        ..color = const Color(0xFF14352D)
        ..strokeWidth = 3,
    );
    canvas.drawRect(
      Rect.fromLTWH(14, 14, size.width - 28, size.height - 28),
      Paint()
        ..color = const Color(0xFFD1B88E).withValues(alpha: .35)
        ..style = PaintingStyle.stroke,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_JacketPainter oldDelegate) => false;
}
