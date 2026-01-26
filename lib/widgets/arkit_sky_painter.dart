import 'package:flutter/material.dart';
import 'dart:ui' as ui;

class StarDot {
  final Offset p;
  final double mag;
  const StarDot({required this.p, required this.mag});
}

class MoonDot {
  final Offset p;
  // 나중에 위상(Phase) 정보를 여기에 추가할 수 있습니다.
  const MoonDot({required this.p});
}

class ArkitSkyPainter extends CustomPainter {
  final List<StarDot> stars;
  final MoonDot? moon;
  final List<({Offset a, Offset b})> lineSegments;
  final List<({Offset p, String label})> labels;

  final Paint _linePaint;
  final Paint _starPaint;
  final Paint _moonPaint;
  final TextStyle _labelStyle; // 텍스트 스타일 재사용

  ArkitSkyPainter({
    required this.stars,
    this.moon,
    required this.lineSegments,
    required this.labels,
  })  : _linePaint = Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.0
          ..strokeCap = StrokeCap.round
          ..color = Colors.white.withOpacity(0.38),
        _starPaint = Paint()..style = PaintingStyle.fill,
        // [수정] 달을 붉은색으로 변경
        _moonPaint = Paint()
          ..style = PaintingStyle.fill
          ..color = Colors.redAccent,
        // [수정] 텍스트 스타일 정의 (별자리와 동일)
        _labelStyle = TextStyle(
          color: Colors.white.withOpacity(0.9),
          fontSize: 13,
          fontWeight: FontWeight.w500,
          shadows: const [
            Shadow(blurRadius: 3, color: Colors.black, offset: Offset(1, 1))
          ],
        );

  @override
  void paint(Canvas canvas, Size size) {
    // 1. 선 그리기
    if (lineSegments.isNotEmpty) {
      final path = Path();
      for (final seg in lineSegments) {
        if (_isSegmentVisible(seg.a, seg.b, size)) {
          path.moveTo(seg.a.dx, seg.a.dy);
          path.lineTo(seg.b.dx, seg.b.dy);
        }
      }
      canvas.drawPath(path, _linePaint);
    }

    // 2. 별 그리기
    for (final s in stars) {
      final p = s.p;
      if (p.dx < -20 ||
          p.dy < -20 ||
          p.dx > size.width + 20 ||
          p.dy > size.height + 20) continue;

      final r = _magToRadius(s.mag);
      final a = _magToAlpha(s.mag);

      if (s.mag < 3.0) {
        _starPaint.color = Colors.white.withOpacity((a * 0.35).clamp(0.0, 0.4));
        canvas.drawCircle(p, r * 2.5, _starPaint);
      }
      _starPaint.color = Colors.white.withOpacity(a);
      canvas.drawCircle(p, r, _starPaint);
    }

    // 3. [수정] 달 그리기 (붉은 원 + 텍스트)
    if (moon != null) {
      final mp = moon!.p;
      if (mp.dx > -40 &&
          mp.dy > -40 &&
          mp.dx < size.width + 40 &&
          mp.dy < size.height + 40) {
        // 달무리 (붉은 Glow)
        _moonPaint.color = Colors.redAccent.withOpacity(0.3);
        canvas.drawCircle(mp, 24.0, _moonPaint);

        // 달 본체 (붉은색)
        _moonPaint.color = Colors.redAccent;
        canvas.drawCircle(mp, 10.0, _moonPaint);

        // [추가] "달" 텍스트 표시
        final tp = TextPainter(
          text: TextSpan(text: "달", style: _labelStyle), // 별자리와 같은 크기/스타일
          textDirection: TextDirection.ltr,
        )..layout();
        // 원 아래쪽에 텍스트 배치
        tp.paint(canvas, mp + Offset(-tp.width / 2, 14));
      }
    }

    // 4. 별자리 이름 그리기
    for (final l in labels) {
      if (l.p.dx < 0 ||
          l.p.dy < 0 ||
          l.p.dx > size.width ||
          l.p.dy > size.height) continue;
      final tp = TextPainter(
        text: TextSpan(text: l.label, style: _labelStyle),
        textDirection: TextDirection.ltr,
        maxLines: 1,
      )..layout();
      tp.paint(canvas, l.p + Offset(-tp.width / 2, 8));
    }
  }

  bool _isSegmentVisible(Offset a, Offset b, Size size) {
    final minX = -50.0;
    final minY = -50.0;
    final maxX = size.width + 50.0;
    final maxY = size.height + 50.0;
    if (a.dx < minX && b.dx < minX) return false;
    if (a.dx > maxX && b.dx > maxX) return false;
    if (a.dy < minY && b.dy < minY) return false;
    if (a.dy > maxY && b.dy > maxY) return false;
    return true;
  }

  double _magToRadius(double mag) {
    final clamped = mag.clamp(-1.0, 6.0);
    return 3.0 - (clamped * 0.35);
  }

  double _magToAlpha(double mag) {
    if (mag > 5.0) return 0.3;
    final clamped = mag.clamp(-1.0, 6.0);
    return (1.0 - (clamped + 1.0) / 7.0).clamp(0.2, 1.0);
  }

  @override
  bool shouldRepaint(covariant ArkitSkyPainter oldDelegate) {
    return oldDelegate.stars != stars ||
        oldDelegate.lineSegments != lineSegments ||
        oldDelegate.labels != labels ||
        oldDelegate.moon != moon;
  }
}
