import 'dart:math' as math;

/// 각도를 0..360으로 정규화
double normDeg(double deg) {
  var d = deg % 360.0;
  if (d < 0) d += 360.0;
  return d;
}

/// -180..180으로 정규화 (각도 차이를 계산할 때 유용)
double normSignedDeg(double deg) {
  var d = deg % 360.0;
  if (d > 180.0) d -= 360.0;
  if (d < -180.0) d += 360.0;
  return d;
}

/// 원형 EMA 필터 (heading/yaw 같이 0~360 wrap되는 값 안정화)
class CircularEma {
  CircularEma({this.alpha = 0.15});

  final double alpha;

  /// 내부 상태는 단위원상의 벡터 (cos, sin)로 저장
  double? _x;
  double? _y;

  bool get hasValue => _x != null && _y != null;

  double? get valueDeg {
    if (!hasValue) return null;
    final ang = math.atan2(_y!, _x!) * 180.0 / math.pi;
    return normDeg(ang);
  }

  void reset() {
    _x = null;
    _y = null;
  }

  void pushDeg(double deg) {
    final r = deg * math.pi / 180.0;
    final cx = math.cos(r);
    final sy = math.sin(r);

    if (!hasValue) {
      _x = cx;
      _y = sy;
      return;
    }

    _x = (1 - alpha) * _x! + alpha * cx;
    _y = (1 - alpha) * _y! + alpha * sy;

    // 길이가 너무 작아지는 것 방지
    final len = math.sqrt(_x! * _x! + _y! * _y!);
    if (len > 1e-9) {
      _x = _x! / len;
      _y = _y! / len;
    }
  }
}

/// 2D 벡터에서 yaw(방위각) 계산.
/// 월드축 가정: x=East, z=North 일 때
/// yawDeg = atan2(x, z)  (0°=North, 90°=East)
double yawFromXz(double x, double z) {
  final ang = math.atan2(x, z) * 180.0 / math.pi;
  return normDeg(ang);
}
