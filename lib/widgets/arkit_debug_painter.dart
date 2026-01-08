import 'package:flutter/material.dart';

class ArkitDebugPainter extends CustomPainter {
  final Map<String, Offset> cardinals; // 'N','E','S','W'
  final List<Offset> horizon;

  ArkitDebugPainter({
    required this.cardinals,
    required this.horizon,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // 중앙 십자선
    final center = Offset(size.width / 2, size.height / 2);
    final crossPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = Colors.greenAccent.withOpacity(0.9);

    canvas.drawLine(center + const Offset(-12, 0), center + const Offset(12, 0),
        crossPaint);
    canvas.drawLine(center + const Offset(0, -12), center + const Offset(0, 12),
        crossPaint);

    // 지평선(Alt=0) polyline
    if (horizon.length >= 2) {
      final hPaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..color = Colors.yellowAccent.withOpacity(0.65);

      final path = Path()..moveTo(horizon.first.dx, horizon.first.dy);
      for (int i = 1; i < horizon.length; i++) {
        path.lineTo(horizon[i].dx, horizon[i].dy);
      }
      canvas.drawPath(path, hPaint);
    }

    // N/E/S/W
    final dotPaint = Paint()
      ..style = PaintingStyle.fill
      ..color = Colors.cyanAccent.withOpacity(0.9);

    for (final entry in cardinals.entries) {
      final p = entry.value;
      canvas.drawCircle(p, 4, dotPaint);

      final tp = TextPainter(
        text: TextSpan(
          text: entry.key,
          style: TextStyle(
            color: Colors.cyanAccent.withOpacity(0.95),
            fontSize: 14,
            shadows: const [Shadow(blurRadius: 2, offset: Offset(0, 1))],
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();

      tp.paint(canvas, p + const Offset(6, -10));
    }
  }

  @override
  bool shouldRepaint(covariant ArkitDebugPainter oldDelegate) {
    return oldDelegate.cardinals != cardinals || oldDelegate.horizon != horizon;
  }
}
