import 'dart:math' as math;
import 'types.dart';

double _deg2rad(double d) => d * math.pi / 180.0;
double _rad2deg(double r) => r * 180.0 / math.pi;

double normalize360(double deg) {
  deg %= 360.0;
  if (deg < 0) deg += 360.0;
  return deg;
}

double normalize180(double deg) {
  deg = ((deg + 180.0) % 360.0) - 180.0;
  return deg;
}

/// Julian Date (UTC 기준 근사)
double julianDate(DateTime utc) {
  final d = utc.day +
      (utc.hour +
              (utc.minute + (utc.second + utc.millisecond / 1000.0) / 60.0) /
                  60.0) /
          24.0;

  int y = utc.year;
  int m = utc.month;
  if (m <= 2) {
    y -= 1;
    m += 12;
  }

  final a = (y / 100).floor();
  final b = 2 - a + (a / 4).floor();

  final jd = (365.25 * (y + 4716)).floor() +
      (30.6001 * (m + 1)).floor() +
      d +
      b -
      1524.5;
  return jd;
}

/// Greenwich Mean Sidereal Time (deg) - POC 근사
double gmstDeg(DateTime utc) {
  final jd = julianDate(utc);
  final t = (jd - 2451545.0) / 36525.0;

  double gmst = 280.46061837 +
      360.98564736629 * (jd - 2451545.0) +
      0.000387933 * t * t -
      (t * t * t) / 38710000.0;

  return normalize360(gmst);
}

/// RA/Dec (deg) -> Alt/Az (deg)
/// - raDeg: 0..360
/// - decDeg: -90..+90
/// - lonDeg: 동경(+) / 서경(-) convention 사용(Geolocator longitude 그대로)
AltAz radecToAltAz({
  required double raDeg,
  required double decDeg,
  required double latDeg,
  required double lonDeg,
  required DateTime utc,
}) {
  // Local Sidereal Time
  final lst = normalize360(gmstDeg(utc) + lonDeg);

  // Hour angle
  final haDeg = normalize180(lst - raDeg);

  final ha = _deg2rad(haDeg);
  final dec = _deg2rad(decDeg);
  final lat = _deg2rad(latDeg);

  final sinAlt = math.sin(dec) * math.sin(lat) +
      math.cos(dec) * math.cos(lat) * math.cos(ha);
  final alt = math.asin(sinAlt);

  final cosAz = (math.sin(dec) - math.sin(alt) * math.sin(lat)) /
      (math.cos(alt) * math.cos(lat));
  final cosAzClamped = cosAz.clamp(-1.0, 1.0);

  double az = math.acos(cosAzClamped);

  // 사분면 보정
  if (math.sin(ha) > 0) {
    az = 2 * math.pi - az;
  }

  return AltAz(_rad2deg(alt), normalize360(_rad2deg(az)));
}
