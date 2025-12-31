import 'dart:ui';

class AltAz {
  final double altDeg; // altitude (deg)
  final double azDeg; // azimuth  (deg, 0=N, 90=E)
  const AltAz(this.altDeg, this.azDeg);
}

class ScreenPoint {
  /// 화면 중심 기준 오프셋 (dx, dy)
  final Offset offset;

  /// 현재 FOV 안에 들어오는지
  final bool visible;

  const ScreenPoint(this.offset, this.visible);
}
