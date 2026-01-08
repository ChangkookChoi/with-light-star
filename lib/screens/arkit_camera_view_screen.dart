import 'dart:math' as math;

import 'package:arkit_plugin/arkit_plugin.dart';
import 'package:flutter/material.dart';
import 'package:vector_math/vector_math_64.dart' as v;

import '../astro/astro_math.dart';
import '../astro/types.dart';
import '../data/catalog_loader.dart';
import '../data/catalog_models.dart';
import '../widgets/arkit_sky_painter.dart';
import '../widgets/arkit_debug_painter.dart';

class ArkitCameraViewScreen extends StatefulWidget {
  const ArkitCameraViewScreen({super.key});

  @override
  State<ArkitCameraViewScreen> createState() => _ArkitCameraViewScreenState();
}

class _ArkitCameraViewScreenState extends State<ArkitCameraViewScreen> {
  ARKitController? _arkit;

  CatalogData? _catalog;
  bool _loading = true;

  Size? _cameraImageSize;

  bool _useHeadingAlignment = true;
  bool _showDebugOverlay = true;

  // ✅ “너무 가득 차 보임”을 줄이는 핵심 파라미터
  double _overlayScale = 0.78; // 0.80~0.92 추천

  // 별 표시 기준 (조절해서 밀도를 줄일 수 있음)
  double _maxMagToDraw = 4.5; // 6.0이면 꽤 많아짐. 4.5~5.5 추천

  // sky-dome 반경(멀수록 parallax 영향 ↓). 투영 위치 자체는 거의 동일하지만 안정성 측면에서 충분히 크게 둡니다.
  static const double _R = 1000.0;

  DateTime _lastUpdate = DateTime.fromMillisecondsSinceEpoch(0);
  bool _busy = false;

  // 결과(화면 좌표)
  List<StarDot> _stars = const [];
  List<({Offset a, Offset b})> _segments = const [];
  List<({Offset p, String label})> _labels = const [];

  // 디버그 오버레이
  Map<String, Offset> _cardinals = const {};
  List<Offset> _horizon = const [];

  // 라인 포함 hip 집합(성능 최적화)
  Set<int> _hipsInLines = <int>{};

  // ===== 위치(임시) =====
  // TODO: 기존 프로젝트 위치 로직이 있으면 연결하세요.
  double _latDeg = 37.5665;
  double _lonDeg = 126.9780;

  @override
  void initState() {
    super.initState();
    _loadCatalog();
  }

  Future<void> _loadCatalog() async {
    setState(() => _loading = true);
    final data = await CatalogLoader.loadOnce();

    final hips = <int>{};
    for (final entry in data.linesByCode.entries) {
      for (final poly in entry.value) {
        hips.addAll(poly);
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
      // debugPrint('trackingState=$state reason=$reason');
    };

    try {
      _cameraImageSize = await controller.getCameraImageResolution();
    } catch (_) {
      _cameraImageSize = null;
    }

    controller.updateAtTime = (_) => _tick();
  }

  void _tick() {
    if (!mounted) return;
    if (_loading || _catalog == null || _arkit == null) return;

    // 15~20fps 정도
    final now = DateTime.now();
    if (now.difference(_lastUpdate).inMilliseconds < 60) return;
    _lastUpdate = now;

    if (_busy) return;
    _busy = true;

    _computeOverlay(_arkit!, _catalog!).whenComplete(() => _busy = false);
  }

  Future<void> _computeOverlay(ARKitController c, CatalogData catalog) async {
    final camPos = await c.cameraPosition();
    if (!mounted || camPos == null) return;

    final nowUtc = DateTime.now().toUtc();

    final screenSize = MediaQuery.sizeOf(context);
    final center = Offset(screenSize.width / 2, screenSize.height / 2);

    Offset? mapAndScale(double px, double py) {
      final p = _mapCameraPixelToScreen(px, py);
      if (p == null) return null;
      // ✅ 화면 중심 기준 “줌아웃” 스케일 적용
      final scaled = center + (p - center) * _overlayScale;
      return scaled;
    }

    // hip -> screen point
    final hipToPt = <int, Offset>{};

    final starDots = <StarDot>[];

    // 별 계산: (라인에 포함된 hip) 또는 (밝은 별)만
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

      // 지평선 아래 제거
      if (altAz.altDeg <= 0) continue;

      final worldPoint = _altAzToWorldPoint(altAz, camPos);

      final projected = await c.projectPoint(worldPoint);
      if (!mounted || projected == null) continue;

      final pt = mapAndScale(projected.x, projected.y);
      if (pt == null) continue;

      hipToPt[hip] = pt;
      starDots.add(StarDot(p: pt, mag: mag));
    }

    // 선 segments
    final segments = <({Offset a, Offset b})>[];
    for (final entry in catalog.linesByCode.entries) {
      for (final poly in entry.value) {
        if (poly.length < 2) continue;
        for (var i = 0; i < poly.length - 1; i++) {
          final a = hipToPt[poly[i]];
          final b = hipToPt[poly[i + 1]];
          if (a == null || b == null) continue;
          segments.add((a: a, b: b));
        }
      }
    }

    // 별자리 라벨(너무 많으면 화면 중심 가까운 상위 N개만)
    final rawLabels = <({Offset p, String label})>[];
    for (final code in catalog.linesByCode.keys) {
      final name = catalog.namesByCode[code]?.displayName() ?? '';
      if (name.isEmpty) continue;

      int count = 0;
      double sx = 0, sy = 0;
      for (final poly in catalog.linesByCode[code]!) {
        for (final hip in poly) {
          final p = hipToPt[hip];
          if (p == null) continue;
          sx += p.dx;
          sy += p.dy;
          count++;
        }
      }
      if (count < 3) continue;

      final centroid = Offset(sx / count, sy / count);
      rawLabels.add((p: centroid, label: name));
    }

    rawLabels.sort((a, b) {
      final da = (a.p - center).distanceSquared;
      final db = (b.p - center).distanceSquared;
      return da.compareTo(db);
    });

    final labels = rawLabels.take(10).toList(); // ✅ 최대 10개만 표시

    // ===== 디버그 오버레이 계산 =====
    Map<String, Offset> cardinals = {};
    List<Offset> horizon = [];

    if (_showDebugOverlay) {
      // N/E/S/W (Alt=0)
      final ne = <String, AltAz>{
        'N': AltAz(0, 0),
        'E': AltAz(0, 90),
        'S': AltAz(0, 180),
        'W': AltAz(0, 270),
      };

      for (final entry in ne.entries) {
        final wp = _altAzToWorldPoint(entry.value, camPos);
        final pr = await c.projectPoint(wp);
        if (!mounted || pr == null) continue;
        final pt = mapAndScale(pr.x, pr.y);
        if (pt == null) continue;
        cardinals[entry.key] = pt;
      }

      // horizon polyline: Alt=0, Az 0..360 step 10
      final pts = <Offset>[];
      for (int az = 0; az <= 360; az += 10) {
        final aa = AltAz(0, az.toDouble());
        final wp = _altAzToWorldPoint(aa, camPos);
        final pr = await c.projectPoint(wp);
        if (!mounted || pr == null) continue;
        final pt = mapAndScale(pr.x, pr.y);
        if (pt == null) continue;

        // 화면 근처만 넣기(너무 멀리 튀면 라인이 이상해짐)
        if (pt.dx < -200 ||
            pt.dy < -200 ||
            pt.dx > screenSize.width + 200 ||
            pt.dy > screenSize.height + 200) {
          continue;
        }
        pts.add(pt);
      }
      horizon = pts;
    }

    setState(() {
      _stars = starDots;
      _segments = segments;
      _labels = labels;
      _cardinals = cardinals;
      _horizon = horizon;
    });
  }

  v.Vector3 _altAzToWorldPoint(AltAz aa, v.Vector3 camPos) {
    final az = aa.azDeg * math.pi / 180.0;
    final alt = aa.altDeg * math.pi / 180.0;

    // ENU
    final e = math.cos(alt) * math.sin(az);
    final n = math.cos(alt) * math.cos(az);
    final u = math.sin(alt);

    // worldAlignment: gravity+heading 기대치: x=E, y=U, z=N
    final dir = v.Vector3(e, u, n);
    if (dir.length == 0) return camPos;
    dir.normalize();

    return v.Vector3(
      camPos.x + dir.x * _R,
      camPos.y + dir.y * _R,
      camPos.z + dir.z * _R,
    );
  }

  Offset? _mapCameraPixelToScreen(double px, double py) {
    final screen = MediaQuery.sizeOf(context);

    final cam = _cameraImageSize;
    if (cam == null || cam.width == 0 || cam.height == 0) {
      if (px.isNaN || py.isNaN) return null;
      return Offset(px, py);
    }

    final sx = px * (screen.width / cam.width);
    final sy = py * (screen.height / cam.height);

    if (sx.isNaN || sy.isNaN) return null;
    return Offset(sx, sy);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
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
            tooltip: _useHeadingAlignment ? 'gravity+heading' : 'gravity',
            onPressed: () =>
                setState(() => _useHeadingAlignment = !_useHeadingAlignment),
            icon:
                Icon(_useHeadingAlignment ? Icons.explore : Icons.explore_off),
          ),
          IconButton(
            tooltip: _showDebugOverlay ? 'debug ON' : 'debug OFF',
            onPressed: () =>
                setState(() => _showDebugOverlay = !_showDebugOverlay),
            icon: Icon(_showDebugOverlay
                ? Icons.bug_report
                : Icons.bug_report_outlined),
          ),
        ],
      ),
      body: Stack(
        children: [
          ARKitSceneView(
            onARKitViewCreated: _onARKitViewCreated,
            showFeaturePoints: false,
            worldAlignment: _useHeadingAlignment
                ? ARWorldAlignment.gravityAndHeading
                : ARWorldAlignment.gravity,
          ),

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

          if (_showDebugOverlay)
            IgnorePointer(
              child: CustomPaint(
                size: Size.infinite,
                painter: ArkitDebugPainter(
                  cardinals: _cardinals,
                  horizon: _horizon,
                ),
              ),
            ),

          // 간단 상태
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
                  'alignment=${_useHeadingAlignment ? "gravity+heading" : "gravity"}  '
                  'scale=${_overlayScale.toStringAsFixed(2)}  mag<=${_maxMagToDraw.toStringAsFixed(1)}',
                  style: const TextStyle(color: Colors.white, fontSize: 12),
                ),
              ),
            ),
          ),

          // “살짝만 작게”를 실시간으로 조절할 수 있게 슬라이더(원하면 삭제 가능)
          Positioned(
            right: 12,
            bottom: 12,
            child: SizedBox(
              width: 180,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _MiniSlider(
                    label: 'Scale',
                    value: _overlayScale,
                    min: 0.78,
                    max: 1.00,
                    onChanged: (v) => setState(() => _overlayScale = v),
                  ),
                  _MiniSlider(
                    label: 'Mag',
                    value: _maxMagToDraw,
                    min: 3.5,
                    max: 6.0,
                    onChanged: (v) => setState(() => _maxMagToDraw = v),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MiniSlider extends StatelessWidget {
  final String label;
  final double value;
  final double min;
  final double max;
  final ValueChanged<double> onChanged;

  const _MiniSlider({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.35),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('$label: ${value.toStringAsFixed(2)}',
                style: const TextStyle(color: Colors.white, fontSize: 12)),
            Slider(
              value: value,
              min: min,
              max: max,
              onChanged: onChanged,
            ),
          ],
        ),
      ),
    );
  }
}
