import 'dart:math' as math;
import 'package:flutter/material.dart';

class ArkitSkyPainter extends CustomPainter {
  final List<dynamic> stars; // _StarDot 리스트(다른 파일 private class라 dynamic 처리)
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
      ..color = Colors.white.withOpacity(0.55);

    final starPaint = Paint()..style = PaintingStyle.fill;

    final labelStyle = TextStyle(
      color: Colors.white.withOpacity(0.92),
      fontSize: 12,
      shadows: const [Shadow(blurRadius: 2, offset: Offset(0, 1))],
    );

    // 선
    for (final seg in lineSegments) {
      canvas.drawLine(seg.a, seg.b, linePaint);
    }

    // 별
    for (final s in stars) {
      // s.p, s.mag 를 기대
      final Offset p = s.p as Offset;
      final double mag = s.mag as double;

      if (p.dx < -50 ||
          p.dy < -50 ||
          p.dx > size.width + 50 ||
          p.dy > size.height + 50) {
        continue;
      }

      // mag가 작을수록 밝음 -> 크게
      // (임의 맵핑, POC용)
      final double r = _magToRadius(mag);

      final double alpha = _magToAlpha(mag);

      starPaint.color = Colors.white.withOpacity(alpha);
      canvas.drawCircle(p, r, starPaint);
    }

    // 라벨
    for (final l in labels) {
      final tp = TextPainter(
        text: TextSpan(text: l.label, style: labelStyle),
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: 240);

      final pos = l.p + const Offset(6, -6);
      tp.paint(canvas, pos);
    }
  }

  double _magToRadius(double mag) {
    // 매우 거칠게: -1 ~ 6 등급
    final clamped = mag.clamp(-1.0, 6.0);
    // 밝을수록 큼
    final t = (6.0 - clamped) / 7.0; // 0..1
    return 1.0 + t * 2.2; // 1.0~3.2
  }

  double _magToAlpha(double mag) {
    final clamped = mag.clamp(-1.0, 6.0);
    final t = (6.0 - clamped) / 7.0; // 0..1
    return (0.35 + t * 0.65).clamp(0.2, 1.0);
  }

  @override
  bool shouldRepaint(covariant ArkitSkyPainter oldDelegate) {
    return oldDelegate.stars != stars ||
        oldDelegate.lineSegments != lineSegments ||
        oldDelegate.labels != labels;
  }
}
