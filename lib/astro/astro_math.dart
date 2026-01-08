import 'dart:math' as math;
import 'types.dart';

double _deg2rad(double d) => d * math.pi / 180.0;
double _rad2deg(double r) => r * 180.0 / math.pi;

double _normalize360(double deg) {
  var x = deg % 360.0;
  if (x < 0) x += 360.0;
  return x;
}

/// RA/Dec(도) + 관측자 위경도(도) + UTC 시간 -> Alt/Az
/// - Az 기준: 0=N, 90=E (북쪽에서 동쪽으로 증가)
AltAz raDecToAltAz({
  required double raDeg,
  required double decDeg,
  required double latDeg,
  required double lonDeg,
  required DateTime utc,
}) {
  // utc가 로컬이면 변환
  final t = utc.isUtc ? utc : utc.toUtc();

  final jd = _julianDate(t);
  final gmstDeg = _gmstDeg(jd);
  final lstDeg = _normalize360(gmstDeg + lonDeg); // 경도 동쪽(+) 가정

  // Hour Angle = LST - RA
  final haDeg = _normalize360(lstDeg - raDeg);

  final ha = _deg2rad(haDeg);
  final dec = _deg2rad(decDeg);
  final lat = _deg2rad(latDeg);

  final sinAlt = math.sin(dec) * math.sin(lat) +
      math.cos(dec) * math.cos(lat) * math.cos(ha);
  final alt = math.asin(sinAlt.clamp(-1.0, 1.0));

  // Azimuth: 0=N, 90=E
  // 공식: az = atan2( sin(HA), cos(HA)*sin(lat) - tan(dec)*cos(lat) )
  final y = math.sin(ha);
  final x = math.cos(ha) * math.sin(lat) - math.tan(dec) * math.cos(lat);
  var az = math.atan2(y, x); // -pi..pi

  // atan2 결과를 "북=0, 동=90"로 정규화
  var azDeg = _normalize360(_rad2deg(az) + 180.0); // 관례/부호 보정
  final altDeg = _rad2deg(alt);

  return AltAz(altDeg, azDeg);
}

/// Julian Date (UTC)
double _julianDate(DateTime utc) {
  // 알고리즘: UTC date/time -> JD
  final y = utc.year;
  final m = utc.month;
  final d = utc.day +
      (utc.hour +
              (utc.minute + (utc.second + utc.millisecond / 1000.0) / 60.0) /
                  60.0) /
          24.0;

  int Y = y;
  int M = m;
  if (M <= 2) {
    Y -= 1;
    M += 12;
  }

  final A = (Y / 100).floor();
  final B = 2 - A + (A / 4).floor();

  final jd = (365.25 * (Y + 4716)).floor().toDouble() +
      (30.6001 * (M + 1)).floor().toDouble() +
      d +
      B -
      1524.5;

  return jd;
}

/// Greenwich Mean Sidereal Time in degrees
double _gmstDeg(double jd) {
  // IAU 간략식(POC 용): GMST(deg)
  final T = (jd - 2451545.0) / 36525.0;
  var gmst = 280.46061837 +
      360.98564736629 * (jd - 2451545.0) +
      0.000387933 * T * T -
      (T * T * T) / 38710000.0;
  gmst = _normalize360(gmst);
  return gmst;
}
