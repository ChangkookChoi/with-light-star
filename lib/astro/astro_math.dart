import 'dart:math' as math;
import 'types.dart';

// ===== 내부 연산용 헬퍼 함수들 (Top-level) =====
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
  final y = math.sin(ha);
  final x = math.cos(ha) * math.sin(lat) - math.tan(dec) * math.cos(lat);
  var az = math.atan2(y, x);

  // atan2 결과를 "북=0, 동=90"로 정규화
  var azDeg = _normalize360(_rad2deg(az) + 180.0);
  final altDeg = _rad2deg(alt);

  return AltAz(altDeg, azDeg);
}

/// Julian Date (UTC)
double _julianDate(DateTime utc) {
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
  final T = (jd - 2451545.0) / 36525.0;
  var gmst = 280.46061837 +
      360.98564736629 * (jd - 2451545.0) +
      0.000387933 * T * T -
      (T * T * T) / 38710000.0;
  gmst = _normalize360(gmst);
  return gmst;
}

// ===== [수정됨] 달 계산 함수를 위한 클래스 추가 =====
class AstroMath {
  /// 날짜(UTC)에 따른 달의 대략적인 적경(RA), 적위(Dec) 계산 (단위: 도)
  static ({double ra, double dec}) getMoonRaDec(DateTime utc) {
    // J2000 기준 일수 계산
    final d = utc.difference(DateTime.utc(2000, 1, 1, 12)).inSeconds / 86400.0;

    // 달의 궤도 요소 (Mean elements)
    final L = (218.316 + 13.176396 * d) % 360.0; // Mean longitude
    final M = (134.963 + 13.064993 * d) % 360.0; // Mean anomaly
    final F = (93.272 + 13.229350 * d) % 360.0; // Mean distance

    final mRad = M * math.pi / 180.0;
    final fRad = F * math.pi / 180.0;

    // 황경 (Ecliptic Longitude)
    final lambda = L + 6.289 * math.sin(mRad);
    // 황위 (Ecliptic Latitude)
    final beta = 5.128 * math.sin(fRad);

    // 황도 경사각 (Obliquity of Ecliptic)
    final epsilon = 23.439 - 0.0000004 * d;

    final lamRad = lambda * math.pi / 180.0;
    final betRad = beta * math.pi / 180.0;
    final epsRad = epsilon * math.pi / 180.0;

    // 황도 좌표 -> 적도 좌표(RA, Dec) 변환
    final x = math.cos(betRad) * math.cos(lamRad);
    final y = math.cos(epsRad) * math.cos(betRad) * math.sin(lamRad) -
        math.sin(epsRad) * math.sin(betRad);
    final z = math.sin(epsRad) * math.cos(betRad) * math.sin(lamRad) +
        math.cos(epsRad) * math.sin(betRad);

    final raRad = math.atan2(y, x);
    final decRad = math.asin(z);

    double ra = raRad * 180.0 / math.pi;
    if (ra < 0) ra += 360.0;
    final dec = decRad * 180.0 / math.pi;

    return (ra: ra, dec: dec);
  }

  /// 달의 나이(월령) 계산 (0.0 ~ 29.53)
  /// 0: 삭(New Moon), 7.4: 상현, 14.8: 보름(Full Moon), 22.1: 하현
  static double getMoonAge(DateTime utc) {
    // 2000년 1월 6일 18:14 UTC가 삭(New Moon)이었습니다.
    // 평균 삭망월 = 29.530588853 일
    final knownNewMoon = DateTime.utc(2000, 1, 6, 18, 14);
    final diff = utc.difference(knownNewMoon).inSeconds / 86400.0;
    final cycle = 29.530588853;

    // 모듈러 연산으로 현재 주기 내의 위치 계산
    double age = diff % cycle;
    if (age < 0) age += cycle;
    return age;
  }

  /// 월령을 바탕으로 달의 위상 이름 반환 (한글)
  static String getMoonPhaseName(double age) {
    if (age < 1.0 || age > 28.5) return "삭 (New Moon)";
    if (age < 6.4) return "초승달";
    if (age < 8.4) return "상현달";
    if (age < 13.8) return "차가는 달";
    if (age < 15.8) return "보름달";
    if (age < 21.1) return "이지러지는 달";
    if (age < 23.1) return "하현달";
    return "그믐달";
  }

  // astro/astro_math.dart 파일의 AstroMath 클래스 내부에 추가

  /// 날짜(UTC)에 따른 태양의 적경(RA), 적위(Dec) 계산
  static ({double ra, double dec}) getSunRaDec(DateTime utc) {
    // J2000 기준 일수
    final d = utc.difference(DateTime.utc(2000, 1, 1, 12)).inSeconds / 86400.0;

    // 태양의 평균 황경 (Mean Longitude)
    final L = (280.460 + 0.9856474 * d) % 360.0;
    // 태양의 평균 근점 이각 (Mean Anomaly)
    final g = (357.528 + 0.9856003 * d) % 360.0;
    final gRad = g * math.pi / 180.0;

    // 황도 경도 (Ecliptic Longitude)
    final lambda = L + 1.915 * math.sin(gRad) + 0.020 * math.sin(2 * gRad);
    final lamRad = lambda * math.pi / 180.0;

    // 황도 경사각 (Obliquity of Ecliptic)
    final epsilon = 23.439 - 0.0000004 * d;
    final epsRad = epsilon * math.pi / 180.0;

    // 적도 좌표계 변환 (RA, Dec)
    final x = math.cos(lamRad);
    final y = math.cos(epsRad) * math.sin(lamRad);
    final z = math.sin(epsRad) * math.sin(lamRad);

    final raRad = math.atan2(y, x);
    final decRad = math.asin(z);

    double ra = raRad * 180.0 / math.pi;
    if (ra < 0) ra += 360.0;
    final dec = decRad * 180.0 / math.pi;

    return (ra: ra, dec: dec);
  }
}
