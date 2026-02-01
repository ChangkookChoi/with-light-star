import 'dart:math' as math;
import 'package:vector_math/vector_math_64.dart' as v;
import '../../astro/astro_math.dart';
import '../../astro/types.dart';

class ArUtils {
  static const double latDeg = 37.5665;
  static const double lonDeg = 126.9780;

  /// 적경/적위 -> 3D 좌표 변환
  static v.Vector3? calculatePosition(
      double ra, double dec, DateTime utc, double distance,
      {bool allowBelowHorizon = false}) {
    // Top-level 함수 직접 호출 (AstroMath.raDecToAltAz 아님)
    final altAz = raDecToAltAz(
        raDeg: ra, decDeg: dec, latDeg: latDeg, lonDeg: lonDeg, utc: utc);

    double limit = allowBelowHorizon ? -60.0 : -5.0;
    if (altAz.altDeg <= limit) return null;

    final azRad = altAz.azDeg * math.pi / 180;
    final altRad = altAz.altDeg * math.pi / 180;

    // ARKit 좌표계 (x: 동, y: 위, z: 남)
    final x = distance * math.cos(altRad) * math.sin(azRad);
    final y = distance * math.sin(altRad);
    final z = -distance * math.cos(altRad) * math.cos(azRad);

    return v.Vector3(x, y, z);
  }

  /// [1. 단순 초기화용] 원점(0,0,0)을 바라보는 회전값
  /// Factory에서 노드를 처음 만들 때 에러가 나지 않도록 사용
  static v.Vector3 calculateSimpleLookAt(v.Vector3 position, [String? name]) {
    // 0,0,0(카메라)을 바라보는 벡터
    final double dx = 0 - position.x;
    final double dy = 0 - position.y;
    final double dz = 0 - position.z;

    double yaw = math.atan2(dx, dz);
    double horizontalDistance = math.sqrt(dx * dx + dz * dz);
    double pitch = math.atan2(dy, horizontalDistance);

    if (name != null) {
      print(
          "${name} position x: ${position.x} y: ${position.y} z: ${position.z}");
      print("${name} position dx: ${dx} dy: ${dy} dz: ${dz}");
      print(
          "${name} position yaw: ${yaw} horizontalDistance: ${horizontalDistance} pitch: ${pitch}");
    }

    // Roll은 0으로 고정
    return v.Vector3(-pitch, yaw, 0);
  }

  /// [2. 실시간 업데이트용] Star Walk 스타일 (Screen-Aligned Billboard)
  /// 매 프레임(_tick)마다 카메라의 위치와 Up 벡터를 받아 계산
  static v.Vector3 calculateScreenAlignedEuler(
      v.Vector3 position, v.Vector3 cameraPosition, v.Vector3 cameraUp) {
    // 1. Forward: 텍스트가 카메라를 바라보는 방향
    final forward = (cameraPosition - position).normalized();

    // 2. Right: 카메라의 Up 벡터와 Forward의 외적 -> 화면의 오른쪽 축
    // (카메라를 기울이면 Right 축도 같이 기울어짐)
    final right = forward.cross(cameraUp).normalized();

    // 3. Up: 텍스트의 진짜 위쪽 방향 (Right x Forward)
    final up = right.cross(forward).normalized();

    // 4. 회전 행렬(Rotation Matrix) 구성
    // (열 우선, Column Major 순서 주의)
    final m = v.Matrix4(
      right.x,
      right.y,
      right.z,
      0,
      up.x,
      up.y,
      up.z,
      0,
      forward.x,
      forward.y,
      forward.z,
      0,
      0,
      0,
      0,
      1,
    );

    // 5. Matrix -> Euler Angles 변환
    final r32 = m.entry(2, 1);
    final r33 = m.entry(2, 2);
    final r31 = m.entry(2, 0);
    final r21 = m.entry(1, 0);
    final r11 = m.entry(0, 0);

    final pitch = math.atan2(r32, r33);
    final yaw = math.atan2(-r31, math.sqrt(r32 * r32 + r33 * r33));
    final roll = math.atan2(r21, r11);

    return v.Vector3(pitch, yaw, roll);
  }
}
