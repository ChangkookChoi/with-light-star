import 'dart:math' as math;

/// Quaternion -> Euler angles (deg)
///
/// 반환:
/// - yaw   : Z축 회전 (방위, -180~180)
/// - pitch : X축 회전 (위/아래)
/// - roll  : Y축 회전 (기기 좌우 기울기)
class EulerAngles {
  final double yawDeg;
  final double pitchDeg;
  final double rollDeg;

  const EulerAngles({
    required this.yawDeg,
    required this.pitchDeg,
    required this.rollDeg,
  });
}

EulerAngles quaternionToEuler({
  required double x,
  required double y,
  required double z,
  required double w,
}) {
  // yaw (Z)
  final siny = 2.0 * (w * z + x * y);
  final cosy = 1.0 - 2.0 * (y * y + z * z);
  final yaw = math.atan2(siny, cosy);

  // pitch (X)
  final sinp = 2.0 * (w * x - y * z);
  double pitch;
  if (sinp.abs() >= 1) {
    pitch = math.pi / 2 * sinp.sign;
  } else {
    pitch = math.asin(sinp);
  }

  // roll (Y)
  final sinr = 2.0 * (w * y + z * x);
  final cosr = 1.0 - 2.0 * (x * x + y * y);
  final roll = math.atan2(sinr, cosr);

  return EulerAngles(
    yawDeg: yaw * 180.0 / math.pi,
    pitchDeg: pitch * 180.0 / math.pi,
    rollDeg: roll * 180.0 / math.pi,
  );
}
