import 'dart:math' as math;
import 'dart:ui';

import 'types.dart';
import 'astro_math.dart';

double _deg2rad(double d) => d * math.pi / 180.0;

/// Alt/Az(별) -> 화면 중심 기준 Offset
///
/// headingDeg: 0=N, 90=E
/// pitchDeg:   "현재 카메라가 바라보는 중심 고도" (지평선=0, 하늘로 들면 +)
/// rollDeg:    화면 회전 (deg)
///
/// 반환 ScreenPoint.offset 은 "화면 중심 기준" 오프셋입니다.
ScreenPoint projectAltAzToScreen({
  required AltAz star,
  required double headingDeg,
  required double pitchDeg,
  required double rollDeg,
  required double hFovDeg,
  required double vFovDeg,
  required Size size,
  bool hideBelowHorizon = false,
}) {
  if (hideBelowHorizon && star.altDeg < 0) {
    return const ScreenPoint(Offset.zero, false);
  }

  // 좌/우 (방위차)
  final dAz = normalize180(star.azDeg - headingDeg);

  // 상/하 (고도차)
  final dAlt = star.altDeg - pitchDeg;

  final visible = (dAz.abs() <= hFovDeg / 2) && (dAlt.abs() <= vFovDeg / 2);
  if (!visible) return const ScreenPoint(Offset.zero, false);

  // roll 적용 전 "월드 기준" 좌표(화면 중심 기준)
  final xWorld = (dAz / (hFovDeg / 2)) * (size.width / 2);
  final yWorld = (-dAlt / (vFovDeg / 2)) * (size.height / 2);

  // roll 보정: 화면이 roll만큼 돌아갔다면 overlay 좌표를 -roll 만큼 회전
  final r = -_deg2rad(rollDeg);
  final cosR = math.cos(r);
  final sinR = math.sin(r);

  final xScreen = xWorld * cosR - yWorld * sinR;
  final yScreen = xWorld * sinR + yWorld * cosR;

  return ScreenPoint(Offset(xScreen, yScreen), true);
}
