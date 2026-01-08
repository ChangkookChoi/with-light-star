import 'package:flutter/material.dart';
import 'dart:math' as math;

class StarDot {
  final Offset p;
  final double mag;
  const StarDot({required this.p, required this.mag});
}

class ArkitSkyPainter extends CustomPainter {
  final List<StarDot> stars;
  final List<({Offset a, Offset b})> lineSegments;
  final List<({Offset p, String label})> labels;

  ArkitSkyPainter({
    required this.stars,
    required this.lineSegments,
    required this.labels,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final linePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0
      ..color = Colors.white.withOpacity(0.38);

    // 선
    for (final seg in lineSegments) {
      canvas.drawLine(seg.a, seg.b, linePaint);
    }

    // 별
    final starPaint = Paint()..style = PaintingStyle.fill;

    for (final s in stars) {
      final p = s.p;
      if (p.dx < -50 ||
          p.dy < -50 ||
          p.dx > size.width + 50 ||
          p.dy > size.height + 50) continue;

      final r = _magToRadius(s.mag);
      final a = _magToAlpha(s.mag);

      // 살짝 glow 느낌(아주 약하게)
      starPaint.color = Colors.white.withOpacity((a * 0.35).clamp(0.05, 0.4));
      canvas.drawCircle(p, r * 2.0, starPaint);

      starPaint.color = Colors.white.withOpacity(a);
      canvas.drawCircle(p, r, starPaint);
    }

    // 라벨
    final labelStyle = TextStyle(
      color: Colors.white.withOpacity(0.88),
      fontSize: 13,
      shadows: const [Shadow(blurRadius: 2, offset: Offset(0, 1))],
    );

    for (final l in labels) {
      final tp = TextPainter(
        text: TextSpan(text: l.label, style: labelStyle),
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: 260);

      tp.paint(canvas, l.p + const Offset(6, -6));
    }
  }

  double _magToRadius(double mag) {
    // -1..6 -> 0..1 (밝을수록 1)
    final clamped = mag.clamp(-1.0, 6.0);
    final t = (6.0 - clamped) / 7.0;
    // 스타워크처럼 과하게 크지 않게
    return 0.9 + t * 2.0; // 0.9..2.9
  }

  double _magToAlpha(double mag) {
    final clamped = mag.clamp(-1.0, 6.0);
    final t = (6.0 - clamped) / 7.0;
    // 어두운 별은 거의 희미하게
    return (0.12 + t * 0.88).clamp(0.08, 1.0);
  }

  @override
  bool shouldRepaint(covariant ArkitSkyPainter oldDelegate) {
    return oldDelegate.stars != stars ||
        oldDelegate.lineSegments != lineSegments ||
        oldDelegate.labels != labels;
  }
}
