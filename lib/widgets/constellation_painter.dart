import 'dart:ui';
import 'package:flutter/material.dart';

import '../astro/types.dart';

class ConstellationPainter extends CustomPainter {
  final Map<String, List<List<int>>> linesByCode;
  final Map<String, String> displayNameByCode; // code -> display name (영문/네이티브)
  final Map<int, ScreenPoint> screenPointsByHip;

  ConstellationPainter({
    required this.linesByCode,
    required this.displayNameByCode,
    required this.screenPointsByHip,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);

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

    linesByCode.forEach((code, polylines) {
      final visibleOffsets = <Offset>[];

      for (final poly in polylines) {
        for (int i = 0; i < poly.length - 1; i++) {
          final aHip = poly[i];
          final bHip = poly[i + 1];

          final a = screenPointsByHip[aHip];
          final b = screenPointsByHip[bHip];

          // 누락(HIP 55203 등) 또는 FOV 밖은 스킵
          if (a == null || b == null) continue;
          if (!a.visible || !b.visible) continue;

          final pa = center + a.offset;
          final pb = center + b.offset;

          canvas.drawLine(pa, pb, linePaint);

          visibleOffsets.add(pa);
          visibleOffsets.add(pb);
        }
      }

      // 라벨 표시: 화면에 선이 그려진 별자리만
      final name = displayNameByCode[code] ?? '';
      if (name.trim().isEmpty) return;
      if (visibleOffsets.isEmpty) return;

      // centroid(평균점) 아래쪽에 배치
      double sx = 0, sy = 0;
      for (final o in visibleOffsets) {
        sx += o.dx;
        sy += o.dy;
      }
      final centroid =
          Offset(sx / visibleOffsets.length, sy / visibleOffsets.length);
      final labelPos = Offset(
        centroid.dx.clamp(8, size.width - 8),
        (centroid.dy + 24).clamp(8, size.height - 8),
      );

      final tp = TextPainter(
        text: TextSpan(text: name, style: labelStyle),
        textDirection: TextDirection.ltr,
        maxLines: 1,
      )..layout(maxWidth: size.width - 16);

      final drawAt = Offset(labelPos.dx - tp.width / 2, labelPos.dy);
      tp.paint(canvas, drawAt);
    });
  }

  @override
  bool shouldRepaint(covariant ConstellationPainter oldDelegate) => true;
}
