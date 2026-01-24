import 'dart:async';
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
  bool _busy = false;

  Size? _cameraImageSize;

  // ===== UX 설정 =====
  final double _overlayScale = 0.88;
  final double _maxMagToDraw = 5.0;
  bool _showDebugOverlay = true;

  static const double _R = 100.0;
  DateTime _lastUpdate = DateTime.fromMillisecondsSinceEpoch(0);

  List<StarDot> _stars = const [];
  List<({Offset a, Offset b})> _segments = const [];
  List<({Offset p, String label})> _labels = const [];
  Map<String, Offset> _cardinals = const {};
  List<Offset> _horizon = const [];

  Set<int> _hipsInLines = {};

  // 서울 기준 위치
  final double _latDeg = 37.5665;
  final double _lonDeg = 126.9780;

  @override
  void initState() {
    super.initState();
    _loadCatalog();
  }

  @override
  void dispose() {
    // 메모리 누수 방지를 위해 컨트롤러 정리
    _arkit?.dispose();
    super.dispose();
  }

  Future<void> _loadCatalog() async {
    setState(() => _loading = true);
    final data = await CatalogLoader.loadOnce();
    final hips = <int>{};
    for (final v in data.linesByCode.values) {
      for (final poly in v) {
        hips.addAll(poly);
      }
    }
    if (mounted) {
      setState(() {
        _catalog = data;
        _hipsInLines = hips;
        _loading = false;
      });
    }
  }

  void _onARKitViewCreated(ARKitController controller) async {
    _arkit = controller;

    try {
      _cameraImageSize = await controller.getCameraImageResolution();
    } catch (_) {
      _cameraImageSize = null;
    }

    controller.updateAtTime = (_) => _tick();
  }

  void _tick() {
    // [최적화] 화면이 살아있지 않거나, 로딩 중이면 연산 스킵
    if (!mounted || _loading || _catalog == null || _arkit == null) return;

    final now = DateTime.now();
    // 16ms (60fps) 제한. 기기 성능에 따라 32ms(30fps)로 늘려도 됨.
    if (now.difference(_lastUpdate).inMilliseconds < 16) return;
    _lastUpdate = now;

    if (_busy) return;
    _busy = true;

    _computeOverlay(_arkit!, _catalog!).whenComplete(() {
      if (mounted) _busy = false;
    });
  }

  Future<void> _computeOverlay(ARKitController c, CatalogData catalog) async {
    final camPos = await c.cameraPosition();
    final camToWorld = await c.pointOfViewTransform();
    if (!mounted || camPos == null || camToWorld == null) return;

    final worldToCam = v.Matrix4.copy(camToWorld)..invert();
    final nowUtc = DateTime.now().toUtc();
    final screen = MediaQuery.sizeOf(context);
    final center = Offset(screen.width / 2, screen.height / 2);

    Offset? mapAndScale(double px, double py) {
      final p = _mapCameraPixelToScreen(px, py);
      if (p == null) return null;
      return center + (p - center) * _overlayScale;
    }

    bool isInFront(v.Vector3 wp) {
      final cp4 = worldToCam.transform(v.Vector4(wp.x, wp.y, wp.z, 1));
      return cp4.z < -0.1;
    }

    // --- 디버그용 방위 표시 ---
    Map<String, Offset> cardinals = {};
    List<Offset> horizon = [];
    if (_showDebugOverlay) {
      const dirs = {'N': 0.0, 'E': 90.0, 'S': 180.0, 'W': 270.0};
      for (final e in dirs.entries) {
        final wp = _altAzToWorldPoint(AltAz(0, e.value), camPos);
        if (!isInFront(wp)) continue;
        final pr = await c.projectPoint(wp);
        if (pr == null) continue;
        final pt = mapAndScale(pr.x, pr.y);
        if (pt != null) cardinals[e.key] = pt;
      }
    }

    // --- 별 계산 ---
    final hipToPt = <int, Offset>{};
    final stars = <StarDot>[];

    // [최적화] 반복문 내부 연산 최소화
    for (final entry in catalog.starsByHip.entries) {
      final hip = entry.key;
      final star = entry.value;
      final mag = star.mag ?? 99;

      if (!_hipsInLines.contains(hip) && mag > _maxMagToDraw) continue;

      final altAz = raDecToAltAz(
        raDeg: star.raDeg,
        decDeg: star.decDeg,
        latDeg: _latDeg,
        lonDeg: _lonDeg,
        utc: nowUtc,
      );

      if (altAz.altDeg <= -5) continue;

      final wp = _altAzToWorldPoint(AltAz(altAz.altDeg, altAz.azDeg), camPos);
      if (!isInFront(wp)) continue;

      final pr = await c.projectPoint(wp);
      if (pr == null) continue;

      final pt = mapAndScale(pr.x, pr.y);
      if (pt == null) continue;

      hipToPt[hip] = pt;
      stars.add(StarDot(p: pt, mag: mag));
    }

    // --- 별자리 선 연결 ---
    final segments = <({Offset a, Offset b})>[];
    for (final entry in catalog.linesByCode.entries) {
      for (final poly in entry.value) {
        // [최적화] 선 연결 시 null 체크를 미리 수행하여 불필요한 리스트 추가 방지
        for (var i = 0; i < poly.length - 1; i++) {
          final a = hipToPt[poly[i]];
          final b = hipToPt[poly[i + 1]];
          if (a != null && b != null) {
            segments.add((a: a, b: b));
          }
        }
      }
    }

    // --- 라벨 계산 ---
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

      if (count >= 1) {
        rawLabels.add((p: Offset(sx / count, sy / count), label: name));
      }
    }

    if (mounted) {
      setState(() {
        _stars = stars;
        _segments = segments;
        _labels = rawLabels;
        _cardinals = cardinals;
        _horizon = horizon;
      });
    }
  }

  v.Vector3 _altAzToWorldPoint(AltAz aa, v.Vector3 camPos) {
    final azRad = aa.azDeg * math.pi / 180;
    final altRad = aa.altDeg * math.pi / 180;

    final x = math.sin(azRad) * math.cos(altRad);
    final y = math.sin(altRad);
    final z = -math.cos(azRad) * math.cos(altRad);

    return camPos + (v.Vector3(x, y, z) * _R);
  }

  Offset? _mapCameraPixelToScreen(double px, double py) {
    final screen = MediaQuery.sizeOf(context);
    final cam = _cameraImageSize;
    if (cam == null || cam.width == 0 || cam.height == 0) return Offset(px, py);
    return Offset(
        px * (screen.width / cam.width), py * (screen.height / cam.height));
  }

  @override
  Widget build(BuildContext context) {
    if (_loading)
      return const Scaffold(
          backgroundColor: Colors.black,
          body: Center(child: CircularProgressIndicator()));

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // 1. AR View
          ARKitSceneView(
            onARKitViewCreated: _onARKitViewCreated,
            configuration: ARKitConfiguration.worldTracking,
            worldAlignment: ARWorldAlignment.gravityAndHeading,
          ),

          // 2. 별자리 오버레이 (RepaintBoundary로 최적화)
          Positioned.fill(
            child: IgnorePointer(
              child: RepaintBoundary(
                // [최적화] 불필요한 전체 리페인팅 방지
                child: CustomPaint(
                  painter: ArkitSkyPainter(
                    stars: _stars,
                    lineSegments: _segments,
                    labels: _labels,
                  ),
                ),
              ),
            ),
          ),

          // 3. 디버그 오버레이
          if (_showDebugOverlay)
            Positioned.fill(
              child: IgnorePointer(
                child: RepaintBoundary(
                  child: CustomPaint(
                    painter: ArkitDebugPainter(
                      cardinals: _cardinals,
                      horizon: _horizon,
                    ),
                  ),
                ),
              ),
            ),

          // 4. [추가됨] 뒤로가기 버튼
          Positioned(
            top: 0,
            left: 0,
            child: SafeArea(
              // 노치 영역 침범 방지
              child: Padding(
                padding: const EdgeInsets.all(8.0),
                child: IconButton(
                  icon: const Icon(Icons.arrow_back_ios_new,
                      color: Colors.white, size: 28),
                  onPressed: () {
                    Navigator.of(context).pop(); // 홈 화면으로 이동
                  },
                ),
              ),
            ),
          ),

          // 5. 안내 텍스트 (위치 약간 조정)
          Positioned(
            top: 60,
            left: 20,
            child: IgnorePointer(
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                    color: Colors.black45,
                    borderRadius: BorderRadius.circular(8)),
                child: const Text(
                  "AR Mode | N:북 E:동",
                  style: TextStyle(color: Colors.white70, fontSize: 12),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
