import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:geolocator/geolocator.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:flutter_compass/flutter_compass.dart';

import 'package:with_light_star/data/catalog_loader.dart';
import 'package:with_light_star/data/catalog_models.dart';

import 'package:with_light_star/astro/types.dart';
import 'package:with_light_star/astro/astro_math.dart';
import 'package:with_light_star/astro/projection.dart';
import 'package:with_light_star/widgets/constellation_painter.dart';

class CameraViewScreen extends StatefulWidget {
  const CameraViewScreen({Key? key}) : super(key: key);

  @override
  State<CameraViewScreen> createState() => _CameraViewScreenState();
}

class _CameraViewScreenState extends State<CameraViewScreen> {
  // -------------------------
  // Camera
  // -------------------------
  CameraController? _camera;

  // -------------------------
  // Heading (Compass)
  // -------------------------
  double _headingDeg = 0.0; // 0~360 (북=0)
  double _headingFilteredDeg = 0.0;
  bool _headingFilterInitialized = false;

  StreamSubscription<CompassEvent>? _compassSub;

  // -------------------------
  // Pitch/Roll (Accelerometer 기반)
  // -------------------------
  double _pitchDegRaw = 0.0;
  double _rollDegRaw = 0.0;

  double _pitchOffsetDeg = 0.0;
  double _rollOffsetDeg = 0.0;

  bool _attitudeCalibrated = false;
  final List<double> _pitchSamples = [];
  final List<double> _rollSamples = [];

  StreamSubscription<AccelerometerEvent>? _accelSub;

  double get _pitchDegCorrected => _pitchDegRaw - _pitchOffsetDeg;
  double get _rollDegCorrected => _rollDegRaw - _rollOffsetDeg;

  // -------------------------
  // Location
  // -------------------------
  Position? _position;
  String? _gpsError;
  StreamSubscription<Position>? _posSub;

  // -------------------------
  // UI refresh timer (30fps)
  // -------------------------
  Timer? _uiTimer;

  // -------------------------
  // Star Catalog
  // -------------------------
  CatalogData? _catalog;
  String? _catalogError;

  // 별자리 이름 표기용: code -> display string
  Map<String, String> _displayNameByCode = {};

  // -------------------------
  // Alt/Az cache (1초마다 갱신)
  // -------------------------
  Timer? _altazTimer;
  final Map<int, AltAz> _altazByHip = {};

  // -------------------------
  // 카메라 시야각(대략)
  // -------------------------
  static const double _hFov = 62.0;
  static const double _vFov = 48.0;

  // -------------------------
  // Lifecycle
  // -------------------------
  @override
  void initState() {
    super.initState();
    _initCamera();
    _initLocation();
    _initOrientation();
    _loadCatalog();
  }

  @override
  void dispose() {
    _uiTimer?.cancel();
    _altazTimer?.cancel();

    _compassSub?.cancel();
    _accelSub?.cancel();
    _posSub?.cancel();

    _camera?.dispose();
    super.dispose();
  }

  // -------------------------
  // Camera init
  // -------------------------
  Future<void> _initCamera() async {
    try {
      final cams = await availableCameras();
      if (cams.isEmpty) return;

      _camera = CameraController(
        cams.first,
        ResolutionPreset.high,
        enableAudio: false,
      );

      await _camera!.initialize();
      if (mounted) setState(() {});
    } catch (e) {
      debugPrint('Camera init error: $e');
    }
  }

  // -------------------------
  // Orientation init
  // -------------------------
  void _initOrientation() {
    // 1) Compass -> heading(yaw)
    _compassSub = FlutterCompass.events?.listen((event) {
      final h = event.heading;
      if (h == null) return;
      updateHeading(h);
    });

    // 2) Accelerometer -> pitch/roll (중력벡터 기반)
    _accelSub = accelerometerEventStream().listen((e) {
      final ax = e.x;
      final ay = e.y;
      final az = e.z;

      // pitch = atan2(-ax, sqrt(ay^2 + az^2))
      final pitchRad = math.atan2(-ax, math.sqrt(ay * ay + az * az));
      _pitchDegRaw = pitchRad * 180.0 / math.pi;

      // roll = atan2(ay, az)
      final rollRad = math.atan2(ay, az);
      _rollDegRaw = rollRad * 180.0 / math.pi;

      // ✅ 자동 캘리브레이션(약 1초)
      if (!_attitudeCalibrated) {
        _pitchSamples.add(_pitchDegRaw);
        _rollSamples.add(_rollDegRaw);

        if (_pitchSamples.length >= 30) {
          final pitchAvg =
              _pitchSamples.reduce((a, b) => a + b) / _pitchSamples.length;
          final rollAvg =
              _rollSamples.reduce((a, b) => a + b) / _rollSamples.length;

          _pitchOffsetDeg = pitchAvg;
          _rollOffsetDeg = rollAvg;

          _attitudeCalibrated = true;
          debugPrint(
            '[ATTITUDE_CALIBRATED] pitchOffset=$_pitchOffsetDeg rollOffset=$_rollOffsetDeg',
          );

          _pitchSamples.clear();
          _rollSamples.clear();
        }
      }
    });

    // 3) UI refresh (30fps)
    _uiTimer = Timer.periodic(const Duration(milliseconds: 33), (_) {
      if (!mounted) return;
      setState(() {});
    });
  }

  // -------------------------
  // Heading smoothing
  // -------------------------
  double _normalize180(double deg) => normalize180(deg);

  void updateHeading(double rawDeg) {
    rawDeg = normalize360(rawDeg);

    if (!_headingFilterInitialized) {
      _headingFilteredDeg = rawDeg;
      _headingDeg = rawDeg;
      _headingFilterInitialized = true;
      return;
    }

    final double delta =
        ((rawDeg - _headingFilteredDeg + 540.0) % 360.0) - 180.0;

    if (delta.abs() < 1.0) return;

    const double alpha = 0.12;
    _headingFilteredDeg = normalize360(_headingFilteredDeg + delta * alpha);
    _headingDeg = _headingFilteredDeg;
  }

  // -------------------------
  // Location init
  // -------------------------
  Future<void> _initLocation() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        if (mounted) setState(() => _gpsError = '위치 서비스가 꺼져 있습니다');
        return;
      }

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }

      if (permission == LocationPermission.denied) {
        if (mounted) setState(() => _gpsError = '위치 권한이 거부되었습니다');
        return;
      }

      if (permission == LocationPermission.deniedForever) {
        if (mounted) {
          setState(() => _gpsError = '위치 권한이 영구 거부되었습니다(설정 필요)');
        }
        return;
      }

      final pos = await Geolocator.getCurrentPosition();
      if (mounted) setState(() => _position = pos);

      _posSub = Geolocator.getPositionStream().listen((p) {
        _position = p;
        if (mounted) setState(() {}); // 위치는 즉시 반영
      });
    } catch (e) {
      if (mounted) setState(() => _gpsError = 'GPS 오류: $e');
    }
  }

  // -------------------------
  // Catalog Load
  // -------------------------
  Future<void> _loadCatalog() async {
    try {
      final data = await CatalogLoader.loadOnce();
      if (!mounted) return;

      // code -> 표시명(native 우선)
      final map = <String, String>{};
      data.namesByCode.forEach((code, name) {
        map[code] = name.displayName();
      });

      setState(() {
        _catalog = data;
        _displayNameByCode = map;
      });

      _startAltAzTimer();
    } catch (e) {
      if (!mounted) return;
      setState(() => _catalogError = e.toString());
    }
  }

  void _startAltAzTimer() {
    _altazTimer?.cancel();

    // catalog/position이 준비된 뒤에만 의미가 있음
    _altazTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      _rebuildAltAzCache();
    });

    // 최초 1회 즉시 계산
    _rebuildAltAzCache();
  }

  void _rebuildAltAzCache() {
    final catalog = _catalog;
    final pos = _position;
    if (catalog == null || pos == null) return;

    final utc = DateTime.now().toUtc();
    final lat = pos.latitude;
    final lon = pos.longitude;

    final next = <int, AltAz>{};

    // stars_min.json에 존재하는 hip만 계산
    catalog.starsByHip.forEach((hip, star) {
      final altaz = radecToAltAz(
        raDeg: star.raDeg,
        decDeg: star.decDeg,
        latDeg: lat,
        lonDeg: lon,
        utc: utc,
      );
      next[hip] = altaz;
    });

    _altazByHip
      ..clear()
      ..addAll(next);
  }

  // -------------------------
  // UI
  // -------------------------
  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;

    if (_camera == null || !_camera!.value.isInitialized) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(child: CircularProgressIndicator()),
      );
    }

    // 투영 결과: hip -> ScreenPoint
    final Map<int, ScreenPoint> screenPointsByHip = {};
    if (_catalog != null && _position != null && _altazByHip.isNotEmpty) {
      _altazByHip.forEach((hip, altaz) {
        screenPointsByHip[hip] = projectAltAzToScreen(
          star: altaz,
          headingDeg: _headingDeg,
          pitchDeg: _pitchDegCorrected,
          rollDeg: _rollDegCorrected,
          hFovDeg: _hFov,
          vFovDeg: _vFov,
          size: size,
        );
      });
    }

    // Catalog 로딩 전이면 painter는 빈 값으로 동작 (아무것도 안 그림)
    final lines = _catalog?.linesByCode ?? const <String, List<List<int>>>{};

    return Scaffold(
      body: Stack(
        children: [
          CameraPreview(_camera!),

          // ✅ 별자리 라인 오버레이
          IgnorePointer(
            child: CustomPaint(
              size: size,
              painter: ConstellationPainter(
                linesByCode: lines,
                displayNameByCode: _displayNameByCode,
                screenPointsByHip: screenPointsByHip,
              ),
            ),
          ),

          // 상단 디버그 UI + 뒤로가기
          _buildTopUI(context),
        ],
      ),
    );
  }

  Widget _buildTopUI(BuildContext context) {
    final gpsText = _gpsError ??
        (_position == null
            ? 'GPS: ...'
            : 'GPS: ${_position!.latitude.toStringAsFixed(5)}, '
                '${_position!.longitude.toStringAsFixed(5)}');

    final catalogText = _catalogError != null
        ? 'Catalog: ERROR ($_catalogError)'
        : (_catalog == null
            ? 'Catalog: loading...'
            : 'Catalog: OK (lines=${_catalog!.linesByCode.length}, stars=${_catalog!.starsByHip.length})');

    final attitudeText = 'Heading=${_headingDeg.toStringAsFixed(1)}° '
        '| PitchCorr=${_pitchDegCorrected.toStringAsFixed(1)}° '
        '| RollCorr=${_rollDegCorrected.toStringAsFixed(1)}°';

    final cacheText = 'AltAz cache: ${_altazByHip.length} stars';

    return Positioned(
      top: 50,
      left: 12,
      right: 12,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              IconButton(
                icon: const Icon(Icons.close, color: Colors.white, size: 30),
                onPressed: () => Navigator.pop(context),
              ),
              Expanded(
                child: Text(
                  gpsText,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white, fontSize: 14),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(attitudeText,
              style: const TextStyle(color: Colors.cyanAccent, fontSize: 13)),
          const SizedBox(height: 2),
          Text(catalogText,
              style: const TextStyle(color: Colors.white70, fontSize: 12)),
          const SizedBox(height: 2),
          Text(cacheText,
              style: const TextStyle(color: Colors.white70, fontSize: 12)),
        ],
      ),
    );
  }
}
