import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';

import '../astro/types.dart';

class ConstellationPainter extends CustomPainter {
  final Map<String, List<List<int>>> linesByCode;
  final Map<String, String> displayNameByCode; // code -> display name
  final Map<int, ScreenPoint> screenPointsByHip;

  // horizon / orientation
  final bool showHorizon;
  final double pitchDeg; // camera pitch (deg, 0 = horizon center)
  final double rollDeg; // camera roll (deg)
  final double vFovDeg; // vertical field of view (deg)

  ConstellationPainter({
    required this.linesByCode,
    required this.displayNameByCode,
    required this.screenPointsByHip,
    required this.showHorizon,
    required this.pitchDeg,
    required this.rollDeg,
    required this.vFovDeg,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);

    // -------------------------
    // Paint definitions
    // -------------------------
    final linePaint = Paint()
      ..color = Colors.cyanAccent.withOpacity(0.85)
      ..strokeWidth = 2.0
      ..style = PaintingStyle.stroke;

    final labelStyle = const TextStyle(
      color: Colors.white,
      fontSize: 12,
      fontWeight: FontWeight.w600,
      shadows: [
        Shadow(blurRadius: 4, color: Colors.black, offset: Offset(0, 1))
      ],
    );

    final horizonPaint = Paint()
      ..color = Colors.orangeAccent.withOpacity(0.85)
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke;

    // -------------------------
    // 1) Horizon
    // -------------------------
    if (showHorizon && vFovDeg > 0) {
      // pitchDeg = 0 → horizon at center
      // dy > 0 → horizon moves down when camera looks up
      final dy = (pitchDeg / vFovDeg) * size.height;

      canvas.save();

      // rotate by roll around screen center
      canvas.translate(center.dx, center.dy);
      canvas.rotate(-rollDeg * math.pi / 180.0);

      // draw long horizon line
      canvas.drawLine(
        Offset(-size.width * 2, -dy),
        Offset(size.width * 2, -dy),
        horizonPaint,
      );

      // small center marker
      canvas.drawCircle(Offset(0, -dy), 8, horizonPaint);

      canvas.restore();
    }

    // -------------------------
    // 2) Constellation lines & labels
    // -------------------------
    linesByCode.forEach((code, polylines) {
      final visibleOffsets = <Offset>[];

      for (final poly in polylines) {
        for (int i = 0; i < poly.length - 1; i++) {
          final aHip = poly[i];
          final bHip = poly[i + 1];

          final a = screenPointsByHip[aHip];
          final b = screenPointsByHip[bHip];

          // missing or out of FOV
          if (a == null || b == null) continue;
          if (!a.visible || !b.visible) continue;

          final pa = center + a.offset;
          final pb = center + b.offset;

          canvas.drawLine(pa, pb, linePaint);

          visibleOffsets.add(pa);
          visibleOffsets.add(pb);
        }
      }

      // label: only when constellation is actually visible
      final name = displayNameByCode[code] ?? '';
      if (name.trim().isEmpty) return;
      if (visibleOffsets.isEmpty) return;

      // centroid of visible segments
      double sx = 0, sy = 0;
      for (final o in visibleOffsets) {
        sx += o.dx;
        sy += o.dy;
      }

      final centroid =
          Offset(sx / visibleOffsets.length, sy / visibleOffsets.length);

      // place label slightly below centroid
      final labelPos = Offset(
        centroid.dx.clamp(12, size.width - 12),
        (centroid.dy + 24).clamp(12, size.height - 12),
      );

      final tp = TextPainter(
        text: TextSpan(text: name, style: labelStyle),
        textDirection: TextDirection.ltr,
        maxLines: 1,
      )..layout(maxWidth: size.width - 24);

      final drawAt = Offset(
        labelPos.dx - tp.width / 2,
        labelPos.dy,
      );

      tp.paint(canvas, drawAt);
    });
  }

  @override
  bool shouldRepaint(covariant ConstellationPainter oldDelegate) {
    return oldDelegate.pitchDeg != pitchDeg ||
        oldDelegate.rollDeg != rollDeg ||
        oldDelegate.screenPointsByHip != screenPointsByHip ||
        oldDelegate.showHorizon != showHorizon;
  }
}
