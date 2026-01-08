import 'dart:math' as math;

import 'package:arkit_plugin/arkit_plugin.dart';
import 'package:flutter/material.dart';
import 'package:vector_math/vector_math_64.dart' as v;

import '../astro/astro_math.dart';
import '../astro/types.dart';
import '../data/catalog_loader.dart';
import '../data/catalog_models.dart';
import '../widgets/arkit_sky_painter.dart';

class ArkitCameraViewScreen extends StatefulWidget {
  const ArkitCameraViewScreen({super.key});

  @override
  State<ArkitCameraViewScreen> createState() => _ArkitCameraViewScreenState();
}

class _ArkitCameraViewScreenState extends State<ArkitCameraViewScreen> {
  ARKitController? _arkit;

  CatalogData? _catalog;
  bool _loading = true;

  // ARKit 카메라 이미지 해상도(픽셀) -> Flutter 화면으로 스케일링에 사용
  Size? _cameraImageSize;

  // UI 토글: 방위(heading) 정렬 사용 여부
  bool _useHeadingAlignment = true;

  // 성능/안정성: 프레임마다 전부 계산하지 않고 15~20fps 정도로 제한
  DateTime _lastUpdate = DateTime.fromMillisecondsSinceEpoch(0);
  bool _busy = false;

  // 결과(화면 좌표)
  List<_StarDot> _stars = const [];
  List<({Offset a, Offset b})> _segments = const [];
  List<({Offset p, String label})> _labels = const [];

  // ====== 위치(위/경도) ======
  // TODO: 지금은 임시 값입니다.
  // 기존 프로젝트에서 geolocator 등으로 lat/lon을 얻는 로직이 있으면 연결하세요.
  double _latDeg = 37.5665;
  double _lonDeg = 126.9780;

  // sky-dome 반경(멀수록 평행이동(parallax) 영향이 작아짐)
  static const double _R = 1000.0;

  // 별 표시 기준(성능/가독성)
  static const double _maxMagToDraw = 6.0; // 6등성까지
  static const double _maxMagToLabelStar =
      1.0; // 1등성 이하만 별 라벨(현재 Star 모델엔 이름이 없어서 사실상 사용 안 함)

  // 선/별자리 라벨을 위해 “라인에 포함되는 hip 집합”을 미리 계산해둠
  Set<int> _hipsInLines = <int>{};

  @override
  void initState() {
    super.initState();
    _loadCatalog();
  }

  Future<void> _loadCatalog() async {
    setState(() {
      _loading = true;
    });

    final data = await CatalogLoader.loadOnce();

    // 라인에 포함되는 hip 모으기 (성능 최적화에 사용)
    final hips = <int>{};
    for (final entry in data.linesByCode.entries) {
      for (final poly in entry.value) {
        for (final hip in poly) {
          hips.add(hip);
        }
      }
    }

    setState(() {
      _catalog = data;
      _hipsInLines = hips;
      _loading = false;
    });
  }

  @override
  void dispose() {
    _arkit?.dispose();
    super.dispose();
  }

  Future<void> _onARKitViewCreated(ARKitController controller) async {
    _arkit = controller;

    controller.onCameraDidChangeTrackingState = (state, reason) {
      // 원하면 로그 확인
      // debugPrint('trackingState=$state reason=$reason');
    };
    controller.onSessionWasInterrupted = () {
      // debugPrint('AR session interrupted');
    };
    controller.onSessionInterruptionEnded = () {
      // debugPrint('AR session interruption ended');
    };
    controller.onError = (msg) {
      // debugPrint('AR error: $msg');
    };

    // 카메라 이미지 해상도(픽셀) 얻기 :contentReference[oaicite:2]{index=2}
    try {
      _cameraImageSize = await controller.getCameraImageResolution();
    } catch (_) {
      _cameraImageSize = null;
    }

    // 프레임 콜백 :contentReference[oaicite:3]{index=3}
    controller.updateAtTime = (double t) {
      _tick();
    };
  }

  void _tick() {
    if (!mounted) return;
    if (_loading) return;
    if (_catalog == null) return;
    final c = _arkit;
    if (c == null) return;

    // 50~70ms => 약 14~20fps
    final now = DateTime.now();
    final dt = now.difference(_lastUpdate).inMilliseconds;
    if (dt < 60) return;
    _lastUpdate = now;

    if (_busy) return;
    _busy = true;

    _computeOverlay(c, _catalog!).whenComplete(() {
      _busy = false;
    });
  }

  Future<void> _computeOverlay(ARKitController c, CatalogData catalog) async {
    // 1) 카메라 pose(월드 공간) 얻기 :contentReference[oaicite:4]{index=4}
    final camToWorld = await c.pointOfViewTransform();
    if (!mounted) return;
    if (camToWorld == null) return;

    // 2) 카메라 위치(translation) 추출
    final camPos =
        await c.cameraPosition(); // :contentReference[oaicite:5]{index=5}
    if (!mounted) return;
    if (camPos == null) return;

    final nowUtc = DateTime.now().toUtc();

    // hip -> screen point
    final Map<int, Offset> hipToPt = {};

    // 별 점 리스트
    final List<_StarDot> starDots = [];

    // 별: (라인에 포함된 hip + 나머지 밝은 별 일부)만 처리하면 성능이 좋아집니다.
    // 여기서는 단순하게 "라인에 포함된 hip 전부 + mag가 밝은 별"만 계산합니다.
    for (final entry in catalog.starsByHip.entries) {
      final hip = entry.key;
      final star = entry.value;

      final mag = star.mag ?? 99.0;

      final shouldConsider = _hipsInLines.contains(hip) || mag <= _maxMagToDraw;

      if (!shouldConsider) continue;
      if (mag > _maxMagToDraw) continue;

      final altAz = raDecToAltAz(
        raDeg: star.raDeg,
        decDeg: star.decDeg,
        latDeg: _latDeg,
        lonDeg: _lonDeg,
        utc: nowUtc,
      );

      // 지평선 아래는 표시 안 함(POC UX)
      if (altAz.altDeg <= 0) continue;

      // Alt/Az -> ENU 방향 -> 월드 포인트 생성
      final worldPoint = _altAzToWorldPoint(altAz, camPos);

      // 3) 월드 포인트를 스크린 픽셀로 투영 :contentReference[oaicite:6]{index=6}
      final projected = await c.projectPoint(worldPoint);
      if (!mounted) return;
      if (projected == null) continue;

      // projected: Vector3(x,y,z) (x,y는 픽셀좌표로 들어오는 형태)
      final px = projected.x;
      final py = projected.y;

      // 4) 카메라 픽셀 -> Flutter 화면 좌표로 매핑
      final screenPt = _mapCameraPixelToScreen(px, py);
      if (screenPt == null) continue;

      hipToPt[hip] = screenPt;
      starDots.add(_StarDot(p: screenPt, mag: mag));
    }

    // 별자리 선 segments 생성 (linesByCode는 hip 리스트 polyline)
    final List<({Offset a, Offset b})> segments = [];
    for (final entry in catalog.linesByCode.entries) {
      for (final poly in entry.value) {
        if (poly.length < 2) continue;
        for (var i = 0; i < poly.length - 1; i++) {
          final aHip = poly[i];
          final bHip = poly[i + 1];
          final a = hipToPt[aHip];
          final b = hipToPt[bHip];
          if (a == null || b == null) continue;
          segments.add((a: a, b: b));
        }
      }
    }

    // 별자리 이름 라벨(코드별로 화면에 잡힌 점들의 centroid)
    final List<({Offset p, String label})> labels = [];
    for (final code in catalog.linesByCode.keys) {
      final name = catalog.namesByCode[code]?.displayName() ?? '';
      if (name.isEmpty) continue;

      // 이 별자리에서 화면에 잡힌 hip들의 평균 위치
      int count = 0;
      double sx = 0;
      double sy = 0;

      final polys = catalog.linesByCode[code]!;
      for (final poly in polys) {
        for (final hip in poly) {
          final p = hipToPt[hip];
          if (p == null) continue;
          sx += p.dx;
          sy += p.dy;
          count++;
        }
      }

      if (count < 3) continue; // 너무 적으면 라벨 생략
      final center = Offset(sx / count, sy / count);

      labels.add((p: center, label: name));
    }

    setState(() {
      _stars = starDots;
      _segments = segments;
      _labels = labels;
    });
  }

  /// Alt/Az(북0 동90) -> ENU 방향벡터 -> 월드 포인트
  /// worldAlignment가 gravityAndHeading일 때,
  /// 월드 축을 (x=East, y=Up, z=North)로 기대하고 매핑합니다.
  v.Vector3 _altAzToWorldPoint(AltAz aa, v.Vector3 camPos) {
    final az = aa.azDeg * math.pi / 180.0;
    final alt = aa.altDeg * math.pi / 180.0;

    // ENU
    final e = math.cos(alt) * math.sin(az);
    final n = math.cos(alt) * math.cos(az);
    final u = math.sin(alt);

    // 월드축 매핑: x=E, y=U, z=N
    final dir = v.Vector3(e, u, n);
    if (dir.length == 0) return camPos;
    dir.normalize();

    // 카메라 위치 + 먼 거리 R
    return v.Vector3(
      camPos.x + dir.x * _R,
      camPos.y + dir.y * _R,
      camPos.z + dir.z * _R,
    );
  }

  /// ARKit projectPoint 결과(카메라 이미지 픽셀 좌표)를 Flutter 화면좌표로 변환
  Offset? _mapCameraPixelToScreen(double px, double py) {
    final screen = MediaQuery.sizeOf(context);

    final cam = _cameraImageSize;
    if (cam == null || cam.width == 0 || cam.height == 0) {
      // 해상도 정보를 못 얻으면, 일단 화면 픽셀로 간주(환경에 따라 오차 가능)
      if (px.isNaN || py.isNaN) return null;
      return Offset(px, py);
    }

    // 단순 스케일 (크롭/레터박스는 일단 무시한 POC)
    final sx = px * (screen.width / cam.width);
    final sy = py * (screen.height / cam.height);

    if (sx.isNaN || sy.isNaN) return null;

    // 화면 밖 너무 멀면 제외
    if (sx < -200 || sx > screen.width + 200) return null;
    if (sy < -200 || sy > screen.height + 200) return null;

    return Offset(sx, sy);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('AR Observation (ARKit)'),
        actions: [
          IconButton(
            tooltip: 'Reload catalog',
            onPressed: _loadCatalog,
            icon: const Icon(Icons.refresh),
          ),
          IconButton(
            tooltip: _useHeadingAlignment ? 'Heading ON' : 'Heading OFF',
            onPressed: () {
              setState(() {
                _useHeadingAlignment = !_useHeadingAlignment;
              });
            },
            icon:
                Icon(_useHeadingAlignment ? Icons.explore : Icons.explore_off),
          ),
        ],
      ),
      body: Stack(
        children: [
          // ARKit 프리뷰
          ARKitSceneView(
            onARKitViewCreated: _onARKitViewCreated,
            showFeaturePoints: false,
            worldAlignment: _useHeadingAlignment
                ? ARWorldAlignment.gravityAndHeading
                : ARWorldAlignment.gravity,
          ),

          // 오버레이
          IgnorePointer(
            child: CustomPaint(
              size: Size.infinite,
              painter: ArkitSkyPainter(
                stars: _stars,
                lineSegments: _segments,
                labels: _labels,
              ),
            ),
          ),

          // 간단 상태 표시(옵션)
          Positioned(
            left: 12,
            bottom: 12,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.45),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                child: Text(
                  'stars=${_stars.length}  lines=${_segments.length}  labels=${_labels.length}\n'
                  'alignment=${_useHeadingAlignment ? "gravity+heading" : "gravity"}',
                  style: const TextStyle(color: Colors.white, fontSize: 12),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StarDot {
  final Offset p;
  final double mag;
  const _StarDot({required this.p, required this.mag});
}
