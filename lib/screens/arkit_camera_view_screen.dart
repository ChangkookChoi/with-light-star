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

  // [중요] 3D 달 위치 설정
  // 별보다 조금 더 가깝게 두어서(90m) 별들이 달 뒤로 숨는 효과를 줄 수도 있음
  static const double _starDistance = 100.0;
  static const double _moonDistance = 90.0;

  DateTime _lastUpdate = DateTime.fromMillisecondsSinceEpoch(0);

  List<StarDot> _stars = const [];
  // MoonDot? _moon; // [삭제] 2D 달 변수 삭제
  ARKitNode? _moonNode; // [추가] 3D 달 노드 관리용

  List<({Offset a, Offset b})> _segments = const [];
  List<({Offset p, String label})> _labels = const [];
  Map<String, Offset> _cardinals = const {};
  List<Offset> _horizon = const [];

  Set<int> _hipsInLines = {};

  final double _latDeg = 37.5665;
  final double _lonDeg = 126.9780;

  @override
  void initState() {
    super.initState();
    _loadCatalog();
  }

  @override
  void dispose() {
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
    if (!mounted || _loading || _catalog == null || _arkit == null) return;
    final now = DateTime.now();
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

    // --- 1. [핵심 변경] 3D 달(Moon) 노드 제어 ---
    // 매 프레임마다 달을 지웠다 그리는 건 비효율적이므로, 위치만 업데이트합니다.
    _updateMoonNode(c, nowUtc, camPos);

    // ----------------------------------------

    // --- 2. 디버그 오버레이 ---
    Map<String, Offset> cardinals = {};
    List<Offset> horizon = [];
    if (_showDebugOverlay) {
      const dirs = {'N': 0.0, 'E': 90.0, 'S': 180.0, 'W': 270.0};
      for (final e in dirs.entries) {
        final wp = _altAzToWorldPoint(AltAz(0, e.value), camPos, _starDistance);
        if (!isInFront(wp)) continue;
        final pr = await c.projectPoint(wp);
        if (pr == null) continue;
        final pt = mapAndScale(pr.x, pr.y);
        if (pt != null) cardinals[e.key] = pt;
      }
    }

    // --- 3. 별 계산 ---
    final hipToPt = <int, Offset>{};
    final stars = <StarDot>[];

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

      final wp = _altAzToWorldPoint(
          AltAz(altAz.altDeg, altAz.azDeg), camPos, _starDistance);
      if (!isInFront(wp)) continue;

      final pr = await c.projectPoint(wp);
      if (pr == null) continue;

      final pt = mapAndScale(pr.x, pr.y);
      if (pt == null) continue;

      hipToPt[hip] = pt;
      stars.add(StarDot(p: pt, mag: mag));
    }

    // --- 4. 선 연결 ---
    final segments = <({Offset a, Offset b})>[];
    for (final entry in catalog.linesByCode.entries) {
      for (final poly in entry.value) {
        for (var i = 0; i < poly.length - 1; i++) {
          final a = hipToPt[poly[i]];
          final b = hipToPt[poly[i + 1]];
          if (a != null && b != null) segments.add((a: a, b: b));
        }
      }
    }

    // --- 5. 라벨 ---
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
      if (count >= 1)
        rawLabels.add((p: Offset(sx / count, sy / count), label: name));
    }

    if (mounted) {
      setState(() {
        _stars = stars;
        // _moon = moonDot; // [삭제됨]
        _segments = segments;
        _labels = rawLabels;
        _cardinals = cardinals;
        _horizon = horizon;
      });
    }
  }

  // === [신규] 달 노드 업데이트 함수 ===
  void _updateMoonNode(ARKitController c, DateTime utc, v.Vector3 camPos) {
    final moonRaDec = AstroMath.getMoonRaDec(utc);
    final moonAltAz = raDecToAltAz(
      raDeg: moonRaDec.ra,
      decDeg: moonRaDec.dec,
      latDeg: _latDeg,
      lonDeg: _lonDeg,
      utc: utc,
    );

    // 지평선 아래면 숨김
    if (moonAltAz.altDeg <= -5) {
      if (_moonNode != null) {
        c.remove(_moonNode!.name);
        _moonNode = null;
      }
      return;
    }

    // 3D 위치 계산
    final moonPos = _altAzToWorldPoint(moonAltAz, camPos, _moonDistance);

    if (_moonNode == null) {
      // --- 노드 생성 ---
      // 3D 모델: 구 (Sphere)
      // 반지름: AR 거리감에 맞춰 조정 (대략 2.0~5.0 사이)
      final material = ARKitMaterial(
        diffuse: ARKitMaterialProperty.image('assets/images/moon_texture.jpg'),
        // 빛 반사 설정 (너무 번들거리지 않게)
        specular: ARKitMaterialProperty.color(Colors.grey),
        shininess: 0.1,
      );

      final sphere = ARKitSphere(
        radius: 4.0, // 달의 크기 (조절 가능)
        materials: [material],
      );

      _moonNode = ARKitNode(
        geometry: sphere,
        position: moonPos,
        name: 'moon_node',
      );

      c.add(_moonNode!);

      // [Tip] 달 위에 "Moon" 텍스트도 3D로 띄우고 싶다면?
      // ARKitText를 자식 노드로 추가하면 됩니다. (일단은 생략)
    } else {
      // --- 위치만 업데이트 (성능 최적화) ---
      _moonNode!.position = moonPos;

      // [심화] 달의 자전축이나 기울기(Rotation)는 구현 복잡도가 높으므로
      // 지금은 항상 카메라를 바라보게(LookAt) 하거나 고정해 둡니다.
      // c.update(_moonNode!); // 필요한 경우 업데이트 호출
    }
  }

  v.Vector3 _altAzToWorldPoint(AltAz aa, v.Vector3 camPos, double distance) {
    final azRad = aa.azDeg * math.pi / 180;
    final altRad = aa.altDeg * math.pi / 180;
    final x = math.sin(azRad) * math.cos(altRad);
    final y = math.sin(altRad);
    final z = -math.cos(azRad) * math.cos(altRad);
    return camPos + (v.Vector3(x, y, z) * distance);
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
          ARKitSceneView(
            onARKitViewCreated: _onARKitViewCreated,
            configuration: ARKitConfiguration.worldTracking,
            worldAlignment: ARWorldAlignment.gravityAndHeading,
          ),
          Positioned.fill(
            child: IgnorePointer(
              child: RepaintBoundary(
                child: CustomPaint(
                  painter: ArkitSkyPainter(
                    stars: _stars,
                    // moon: _moon, // [삭제됨] Painter에는 더 이상 전달 안 함
                    lineSegments: _segments,
                    labels: _labels,
                  ),
                ),
              ),
            ),
          ),
          // ... (나머지 UI 코드는 동일)
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
          Positioned(
            top: 0,
            left: 0,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(8.0),
                child: IconButton(
                  icon: const Icon(Icons.arrow_back_ios_new,
                      color: Colors.white, size: 28),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ),
            ),
          ),
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
                child: const Text("AR Mode | N:북 E:동",
                    style: TextStyle(color: Colors.white70, fontSize: 12)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
