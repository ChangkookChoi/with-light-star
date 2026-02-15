import 'dart:math' as math;
import 'package:vector_math/vector_math_64.dart' as v;
import '../../astro/astro_math.dart'; // [필수] astro_math의 raDecToAltAz 사용

class ArUtils {
  /// [위치 계산 수정본]
  /// RA/Dec(우주 절대 좌표) -> Alt/Az(내 눈 기준 좌표) -> ARKit(3D 좌표)
  static v.Vector3? calculatePosition(
    double raDeg,
    double decDeg,
    DateTime time,
    double distance,
    double lat, // [추가] 사용자 위도
    double lon, // [추가] 사용자 경도
    {
    bool allowBelowHorizon = true,
  }) {
    // 1. 천문학적 계산: 내 위치(Lat, Lon)에서 별이 어디(Alt, Az)에 떠 있는지 계산
    final altAz = raDecToAltAz(
      raDeg: raDeg,
      decDeg: decDeg,
      latDeg: lat,
      lonDeg: lon,
      utc: time.isUtc ? time : time.toUtc(),
    );

    // 2. ARKit 좌표계 변환 (Right-handed, Y-up)
    // ARKit 기준: -Z가 북쪽(North), +X가 동쪽(East), +Y가 하늘(Zenith)
    // worldAlignment: gravityAndHeading 옵션을 켰을 때 기준입니다.

    final altRad = altAz.altDeg * math.pi / 180.0;
    final azRad = altAz.azDeg * math.pi / 180.0;

    // 지평선 아래 필터링
    if (!allowBelowHorizon && altAz.altDeg < 0) return null;

    // 3D 좌표 변환 (구면 좌표계 -> 직교 좌표계)
    // y = 높이 (Altitude)
    final y = distance * math.sin(altRad);

    // 수평면에서의 거리 (projected distance)
    final hDist = distance * math.cos(altRad);

    // x, z 계산 (Azimuth는 북쪽 0도 기준 시계방향)
    // ARKit에서 북쪽은 -Z, 동쪽은 +X
    // Az 0(북) -> x=0, z=-hDist
    // Az 90(동) -> x=hDist, z=0
    final x = hDist * math.sin(azRad);
    final z = -hDist * math.cos(azRad);

    return v.Vector3(x, y, z);
  }

  // ... (달 계산 로직은 astro_math로 통합 권장)
  // 임시로 유지한다면 아래 함수도 AstroMath.getMoonRaDec를 쓰도록 변경 추천
  static Map<String, double> calculateMoonRaDec(DateTime time) {
    final moon = AstroMath.getMoonRaDec(time);
    return {'ra': moon.ra, 'dec': moon.dec};
  }
}
