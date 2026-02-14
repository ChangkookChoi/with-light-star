import 'dart:math' as math;
import 'package:vector_math/vector_math_64.dart' as v;

class ArUtils {
  /// [위치 계산] RA(적경), Dec(적위) -> ARKit 3D 좌표 (x, y, z) 변환
  static v.Vector3? calculatePosition(
      double raDeg, double decDeg, DateTime time, double distance,
      {bool allowBelowHorizon = true}) {
    final rad = math.pi / 180.0;
    final alpha = raDeg * rad;
    final delta = decDeg * rad;

    // 그리니치 평균 항성시 (GMST) 계산
    final d = time.difference(DateTime.utc(2000, 1, 1, 12)).inMilliseconds /
        86400000.0;
    final gmst = (18.697374558 + 24.06570982441908 * d) % 24;
    final gmstRad = (gmst * 15) * rad;

    // 시간각 (LHA)
    final lha = gmstRad - alpha;

    // ARKit 좌표계 변환 (Y-up, -Z North)
    final x = distance * math.cos(delta) * math.sin(lha);
    final y = distance * math.sin(delta);
    final z = -distance * math.cos(delta) * math.cos(lha);

    // 지평선 아래 필터링
    if (!allowBelowHorizon && y < 0) return null;

    return v.Vector3(x, y, z);
  }

  /// [달 위치 계산] 현재 시간 기준 달의 좌표 반환
  static Map<String, double> calculateMoonRaDec(DateTime time) {
    double d =
        time.difference(DateTime.utc(2000, 1, 1, 12)).inSeconds / 86400.0;

    double L = (218.316 + 13.176396 * d) % 360;
    double M = (134.963 + 13.064993 * d) % 360;
    double F = (93.272 + 13.229350 * d) % 360;

    double rad = math.pi / 180.0;
    double lon = L + 6.289 * math.sin(M * rad);
    double lat = 5.128 * math.sin(F * rad);

    double epsilon = 23.44 * rad;
    double lonRad = lon * rad;
    double latRad = lat * rad;

    double x = math.cos(latRad) * math.cos(lonRad);
    double y = math.cos(epsilon) * math.cos(latRad) * math.sin(lonRad) -
        math.sin(epsilon) * math.sin(latRad);
    double z = math.sin(epsilon) * math.cos(latRad) * math.sin(lonRad) +
        math.cos(epsilon) * math.sin(latRad);

    double ra = math.atan2(y, x) / rad;
    double dec = math.asin(z) / rad;

    if (ra < 0) ra += 360;

    return {'ra': ra, 'dec': dec};
  }
}
