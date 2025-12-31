import 'dart:math' as math;

import 'types.dart';

double _deg2rad(double d) => d * math.pi / 180.0;
double _rad2deg(double r) => r * 180.0 / math.pi;

/// [0, 360)
double normalize360(double deg) {
  deg %= 360.0;
  if (deg < 0) deg += 360.0;
  return deg;
}

/// (-180, 180]
double normalize180(double deg) {
  deg = ((deg + 180.0) % 360.0) - 180.0;
  return deg;
}

/// Julian Day (UTC)
double julianDayUtc(DateTime utc) {
  // utc는 반드시 UTC로 들어온다고 가정
  final y0 = utc.year;
  final m0 = utc.month;
  final d0 = utc.day;

  int y = y0;
  int m = m0;
  if (m <= 2) {
    y -= 1;
    m += 12;
  }

  final A = (y / 100).floor();
  final B = 2 - A + (A / 4).floor();

  final dayFraction = (utc.hour +
          utc.minute / 60.0 +
          (utc.second + utc.millisecond / 1000.0) / 3600.0) /
      24.0;

  final JD = (365.25 * (y + 4716)).floorToDouble() +
      (30.6001 * (m + 1)).floorToDouble() +
      d0 +
      B -
      1524.5 +
      dayFraction;

  return JD;
}

/// Greenwich Mean Sidereal Time (deg) from Julian Day
double gmstDegFromJd(double jd) {
  // IAU 1982-ish approximation (관측/AR용으로 충분)
  final T = (jd - 2451545.0) / 36525.0;

  double gmst = 280.46061837 +
      360.98564736629 * (jd - 2451545.0) +
      0.000387933 * T * T -
      (T * T * T) / 38710000.0;

  return normalize360(gmst);
}

/// Local Sidereal Time (deg)
double lstDeg({
  required DateTime utc,
  required double lonDeg,
}) {
  final jd = julianDayUtc(utc);
  final gmst = gmstDegFromJd(jd);
  return normalize360(gmst + lonDeg);
}

/// Convert RA/Dec (deg) to Alt/Az (deg) for an observer at lat/lon (deg) at given UTC.
///
/// - azDeg: 0=N, 90=E
AltAz radecToAltAz({
  required double raDeg,
  required double decDeg,
  required double latDeg,
  required double lonDeg,
  required DateTime utc,
}) {
  final lat = _deg2rad(latDeg);
  final dec = _deg2rad(decDeg);

  final lst = lstDeg(utc: utc, lonDeg: lonDeg);
  final haDeg = normalize180(lst - raDeg); // hour angle in degrees (-180..180]
  final ha = _deg2rad(haDeg);

  // altitude
  final sinAlt = math.sin(dec) * math.sin(lat) +
      math.cos(dec) * math.cos(lat) * math.cos(ha);
  final sinAltClamped = sinAlt.clamp(-1.0, 1.0);
  final alt = math.asin(sinAltClamped);

  // azimuth
  final cosAz = (math.sin(dec) - math.sin(alt) * math.sin(lat)) /
      (math.cos(alt) * math.cos(lat));
  final cosAzClamped = cosAz.clamp(-1.0, 1.0);
  double az = math.acos(cosAzClamped);

  // quadrant correction
  if (math.sin(ha) > 0) {
    az = 2 * math.pi - az;
  }

  return AltAz(_rad2deg(alt), normalize360(_rad2deg(az)));
}
