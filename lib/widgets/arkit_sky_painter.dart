import 'package:flutter/material.dart';
import 'dart:ui' as ui; // PointMode 사용을 위해 필요

class StarDot {
  final Offset p;
  final double mag;
  const StarDot({required this.p, required this.mag});
}

class ArkitSkyPainter extends CustomPainter {
  final List<StarDot> stars;
  final List<({Offset a, Offset b})> lineSegments;
  final List<({Offset p, String label})> labels;

  // 페인트 객체를 매번 생성하지 않도록 미리 정의 (메모리 절약)
  final Paint _linePaint;
  final Paint _starPaint;

  ArkitSkyPainter({
    required this.stars,
    required this.lineSegments,
    required this.labels,
  })  : _linePaint = Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.0
          ..strokeCap = StrokeCap.round
          ..color = Colors.white.withOpacity(0.38),
        _starPaint = Paint()..style = PaintingStyle.fill;

  @override
  void paint(Canvas canvas, Size size) {
    // 1. [최적화] 선 그리기 (Batch Processing)
    // 선을 하나씩(drawLine) 그리는 대신, 경로(Path) 하나에 담아서 한 번에 그립니다.
    if (lineSegments.isNotEmpty) {
      final path = Path();
      for (final seg in lineSegments) {
        // 화면 밖의 선은 Path에 추가하지 않음 (간단한 컬링)
        if (_isSegmentVisible(seg.a, seg.b, size)) {
          path.moveTo(seg.a.dx, seg.a.dy);
          path.lineTo(seg.b.dx, seg.b.dy);
        }
      }
      canvas.drawPath(path, _linePaint);
    }

    // 2. [최적화] 별 그리기
    for (final s in stars) {
      final p = s.p;
      // 화면 밖의 별은 그리지 않음
      if (p.dx < -20 ||
          p.dy < -20 ||
          p.dx > size.width + 20 ||
          p.dy > size.height + 20) continue;

      final r = _magToRadius(s.mag);
      final a = _magToAlpha(s.mag);

      // [성능 핵심]
      // 모든 별에 Glow(빛 번짐)를 주지 않고, 밝은 별(3등급 이하)에만 줍니다.
      // 어두운 별은 계산과 그리기 횟수를 절반으로 줄입니다.
      if (s.mag < 3.0) {
        _starPaint.color = Colors.white.withOpacity((a * 0.35).clamp(0.0, 0.4));
        canvas.drawCircle(p, r * 2.5, _starPaint);
      }

      // 별의 중심(Core)
      _starPaint.color = Colors.white.withOpacity(a);
      canvas.drawCircle(p, r, _starPaint);
    }

    // 3. 라벨 그리기
    final labelStyle = TextStyle(
      color: Colors.white.withOpacity(0.9),
      fontSize: 13,
      fontWeight: FontWeight.w500,
      shadows: const [
        Shadow(blurRadius: 3, color: Colors.black, offset: Offset(1, 1))
      ],
    );

    for (final l in labels) {
      // 화면 안에 있는 라벨만 그림
      if (l.p.dx < 0 ||
          l.p.dy < 0 ||
          l.p.dx > size.width ||
          l.p.dy > size.height) continue;

      final tp = TextPainter(
        text: TextSpan(text: l.label, style: labelStyle),
        textDirection: TextDirection.ltr,
        maxLines: 1,
      );

      tp.layout(); // maxWidth 제한 제거 (성능 향상 미비하지만 텍스트 잘림 방지)

      // 텍스트 중심을 잡기 위해 오프셋 조정
      tp.paint(canvas, l.p + Offset(-tp.width / 2, 8));
    }
  }

  // 선이 화면 안에 조금이라도 걸치는지 확인
  bool _isSegmentVisible(Offset a, Offset b, Size size) {
    final minX = -50.0;
    final minY = -50.0;
    final maxX = size.width + 50.0;
    final maxY = size.height + 50.0;

    // 두 점이 모두 화면 왼쪽/오른쪽/위/아래에 있으면 안 보임
    if (a.dx < minX && b.dx < minX) return false;
    if (a.dx > maxX && b.dx > maxX) return false;
    if (a.dy < minY && b.dy < minY) return false;
    if (a.dy > maxY && b.dy > maxY) return false;

    return true;
  }

  double _magToRadius(double mag) {
    final clamped = mag.clamp(-1.0, 6.0);
    // return 값 계산 단순화
    return 3.0 - (clamped * 0.35); // 밝을수록 크기 (약 1.0 ~ 3.5 사이)
  }

  double _magToAlpha(double mag) {
    // 밝기 계산 로직 단순화
    if (mag > 5.0) return 0.3; // 아주 어두운 별은 고정 투명도
    final clamped = mag.clamp(-1.0, 6.0);
    return (1.0 - (clamped + 1.0) / 7.0).clamp(0.2, 1.0);
  }

  @override
  bool shouldRepaint(covariant ArkitSkyPainter oldDelegate) {
    // 데이터 내용이 바뀌었을 때만 다시 그림
    return oldDelegate.stars != stars ||
        oldDelegate.lineSegments != lineSegments ||
        oldDelegate.labels != labels;
  }
}
