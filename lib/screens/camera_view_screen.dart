import 'dart:async';
import 'dart:math' as math;

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:motion_sensors/motion_sensors.dart' hide AccelerometerEvent;

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
  // Camera & FPS
  // -------------------------
  CameraController? _camera;
  double _cameraFps = 0.0;
  DateTime? _lastCameraFrameTime;

  // -------------------------
  // Sensor Hz (actual event rate)
  // -------------------------
  double _sensorHz = 0.0;
  DateTime? _lastSensorTime;

  // -------------------------
  // Sensors
  // -------------------------
  final MotionSensors _motionSensors = MotionSensors();
  StreamSubscription<AbsoluteOrientationEvent>? _absOriSub;
  StreamSubscription<AccelerometerEvent>? _accelSub;

  // yaw (rad) from motion_sensors (we'll convert to deg for display/projection)
  double _yawRad = 0.0;

  // pitch / roll: we compute from accelerometer (deg)
  // raw = latest computed from accelerometer event
  double _rawPitchDeg = 0.0;
  double _rawRollDeg = 0.0;

  // filtered = what we actually use for rendering (deg)
  double _pitchDeg = 0.0;
  double _rollDeg = 0.0;

  // smoothing factor (0~1) - "how quickly filtered follows raw"
  static const double _filterFactor = 0.15;

  // -------------------------
  // UI tick (sync to camera fps)
  // -------------------------
  Timer? _uiTimer;
  int _uiTickMs =
      33; // initial fallback; will be replaced by camera fps-derived
  DateTime? _lastUiTickTime;

  // -------------------------
  // Location / Catalog
  // -------------------------
  Position? _position;
  StreamSubscription<Position>? _posSub;

  CatalogData? _catalog;
  Map<String, String> _displayNameByCode = {};
  Timer? _altazTimer;
  final Map<int, AltAz> _altazByHip = {};

  static const double _hFov = 62.0;
  static const double _vFov = 48.0;

  @override
  void initState() {
    super.initState();
    _initCamera();
    _initLocation();
    _loadCatalog();
    _initYawSensor();
    _initHorizonSensors();

    // 시작은 임시 30fps로, 이후 카메라 FPS 측정되면 자동으로 따라감
    _startOrUpdateUiTimer(force: true);
  }

  @override
  void dispose() {
    _uiTimer?.cancel();
    _altazTimer?.cancel();
    _absOriSub?.cancel();
    _accelSub?.cancel();
    _posSub?.cancel();

    _camera?.stopImageStream();
    _camera?.dispose();
    super.dispose();
  }

  // -------------------------
  // Camera (FPS 측정)
  // -------------------------
  Future<void> _initCamera() async {
    final cams = await availableCameras();
    if (cams.isEmpty) return;

    _camera = CameraController(
      cams.first,
      ResolutionPreset.high,
      enableAudio: false,
    );

    await _camera!.initialize();

    // 실제 카메라 프레임 속도 측정 (하드코딩 X)
    _camera!.startImageStream((_) {
      final now = DateTime.now();
      if (_lastCameraFrameTime != null) {
        final dtMs = now.difference(_lastCameraFrameTime!).inMilliseconds;
        if (dtMs > 0) {
          final fps = 1000.0 / dtMs;

          // "실제값"은 fps이지만, 값이 튀지 않게 최소한의 완만한 평균만 적용(표시 안정)
          // (이건 보정이라기보단 통계적 안정화이며, 원시 dt 기반으로 계산한 fps에서 나온 값입니다.)
          _cameraFps =
              (_cameraFps == 0.0) ? fps : (_cameraFps * 0.9 + fps * 0.1);

          // 카메라 FPS를 기반으로 UI tick 주기를 자동 업데이트 (sync)
          _startOrUpdateUiTimer();
        }
      }
      _lastCameraFrameTime = now;
    });

    if (mounted) setState(() {});
  }

  // -------------------------
  // Yaw only (motion_sensors)
  // -------------------------
  void _initYawSensor() {
    // motion_sensors는 "원시 이벤트"이므로 여기서는 setState 하지 않습니다.
    // UI는 카메라 FPS 기반 tick에서 갱신됩니다.
    _motionSensors.absoluteOrientationUpdateInterval = 33333; // 요청값(약 30Hz)
    _absOriSub = _motionSensors.absoluteOrientation.listen((e) {
      _yawRad = e.yaw;
    });
  }

  // -------------------------
  // Pitch / Roll (accelerometer)
  // -------------------------
  void _initHorizonSensors() {
    _accelSub = accelerometerEvents.listen((e) {
      final now = DateTime.now();

      // 실제 이벤트 수신 간격으로 Hz 계산 (실제값)
      if (_lastSensorTime != null) {
        final dtMs = now.difference(_lastSensorTime!).inMilliseconds;
        if (dtMs > 0) {
          final hz = 1000.0 / dtMs;
          _sensorHz = (_sensorHz == 0.0) ? hz : (_sensorHz * 0.9 + hz * 0.1);
        }
      }
      _lastSensorTime = now;

      // 예제와 동일한 방식: 중력 벡터 기반 pitch/roll
      final rawRoll = math.atan2(e.x, e.y) * 180.0 / math.pi;
      final rawPitch = math.atan2(
            -e.z,
            math.sqrt(e.x * e.x + e.y * e.y),
          ) *
          180.0 /
          math.pi;

      // "raw"만 갱신. 렌더링 값(filtered)은 카메라 FPS tick에서 업데이트합니다.
      _rawPitchDeg = rawPitch;
      _rawRollDeg = rawRoll;
    });
  }

  // -------------------------
  // UI tick (sync to camera fps)
  // -------------------------
  void _startOrUpdateUiTimer({bool force = false}) {
    // 카메라 fps -> 목표 tick ms
    // 1) 카메라 fps가 아직 0이면 fallback(33ms)
    // 2) 너무 작은/큰 값 방지: 15~60fps 범위로 clamp
    final fps = (_cameraFps > 0.0) ? _cameraFps : 30.0;
    final clamped = fps.clamp(15.0, 60.0);
    final targetMs = (1000.0 / clamped).round();

    // 너무 자주 재시작하지 않도록, 변화가 꽤 있을 때만 갱신
    final shouldRestart =
        force || (_uiTimer == null) || ((targetMs - _uiTickMs).abs() >= 4);
    if (!shouldRestart) return;

    _uiTickMs = targetMs;
    _uiTimer?.cancel();
    _lastUiTickTime = DateTime.now();

    _uiTimer = Timer.periodic(Duration(milliseconds: _uiTickMs), (_) {
      if (!mounted) return;

      // 카메라 FPS tick마다 raw -> filtered로 스무딩 (센서 Hz가 낮아도 렌더는 부드럽게)
      final now = DateTime.now();
      final dtMs = _lastUiTickTime == null
          ? _uiTickMs
          : now.difference(_lastUiTickTime!).inMilliseconds;
      _lastUiTickTime = now;

      // dt에 따른 alpha 조정(하드코딩 alpha 대신 tick 기반으로 약간 보정)
      // dt가 커지면 따라가는 비율을 조금 늘려서 체감 동기화 개선
      final dt = (dtMs <= 0) ? 0.033 : (dtMs / 1000.0);
      final alpha = 1.0 -
          math.pow(1.0 - _filterFactor, (dt / 0.033)).toDouble(); // 33ms 기준 확장
      final a = alpha.clamp(0.02, 0.35);

      _pitchDeg = _pitchDeg * (1.0 - a) + _rawPitchDeg * a;
      _rollDeg = _rollDeg * (1.0 - a) + _rawRollDeg * a;

      // 여기서만 setState → 렌더링 프레임을 카메라 FPS에 맞춤
      setState(() {});
    });
  }

  // -------------------------
  // Location & Catalog
  // -------------------------
  Future<void> _initLocation() async {
    final pos = await Geolocator.getCurrentPosition();
    _position = pos;

    // 위치 변화는 느리므로 setState 유지
    _posSub = Geolocator.getPositionStream().listen((p) {
      if (!mounted) return;
      setState(() => _position = p);
    });
  }

  Future<void> _loadCatalog() async {
    final data = await CatalogLoader.loadOnce();
    final map = <String, String>{};
    data.namesByCode.forEach((k, v) => map[k] = v.displayName());

    if (!mounted) return;
    setState(() {
      _catalog = data;
      _displayNameByCode = map;
    });

    _startAltAzTimer();
  }

  void _startAltAzTimer() {
    _altazTimer?.cancel();
    _altazTimer =
        Timer.periodic(const Duration(seconds: 1), (_) => _rebuildAltAzCache());
    _rebuildAltAzCache();
  }

  void _rebuildAltAzCache() {
    if (_catalog == null || _position == null) return;
    final utc = DateTime.now().toUtc();

    _altazByHip.clear();
    _catalog!.starsByHip.forEach((hip, star) {
      _altazByHip[hip] = radecToAltAz(
        raDeg: star.raDeg,
        decDeg: star.decDeg,
        latDeg: _position!.latitude,
        lonDeg: _position!.longitude,
        utc: utc,
      );
    });
  }

  // -------------------------
  // Derived (for projection / display)
  // -------------------------
  double get _headingDeg => normalize360((-_yawRad) * 180.0 / math.pi);
  double get _yawDeg => (-_yawRad) * 180.0 / math.pi;

  @override
  Widget build(BuildContext context) {
    if (_camera == null || !_camera!.value.isInitialized) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final size = MediaQuery.of(context).size;

    // projection
    final Map<int, ScreenPoint> screenPointsByHip = {};
    _altazByHip.forEach((hip, altaz) {
      if (altaz.altDeg < -5) return;
      screenPointsByHip[hip] = projectAltAzToScreen(
        star: altaz,
        headingDeg: _headingDeg,
        pitchDeg: _pitchDeg,
        rollDeg: _rollDeg,
        hFovDeg: _hFov,
        vFovDeg: _vFov,
        size: size,
        hideBelowHorizon: true,
      );
    });

    return Scaffold(
      body: Stack(
        children: [
          CameraPreview(_camera!),
          IgnorePointer(
            child: CustomPaint(
              size: size,
              painter: ConstellationPainter(
                linesByCode: _catalog?.linesByCode ?? {},
                displayNameByCode: _displayNameByCode,
                screenPointsByHip: screenPointsByHip,
                showHorizon: true,
                pitchDeg: _pitchDeg,
                rollDeg: _rollDeg,
                vFovDeg: _vFov,
              ),
            ),
          ),
          _buildOverlayPanel(context),
        ],
      ),
    );
  }

  Widget _buildOverlayPanel(BuildContext context) {
    return Positioned(
      top: 50,
      left: 12,
      right: 12,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.black54,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                IconButton(
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  icon: const Icon(Icons.close, color: Colors.white, size: 26),
                  onPressed: () => Navigator.pop(context),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'LAT: ${_position?.latitude.toStringAsFixed(4)}  '
                    'LON: ${_position?.longitude.toStringAsFixed(4)}',
                    style: const TextStyle(color: Colors.white, fontSize: 13),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),

            // yaw/pitch/roll 표시
            Text(
              'Yaw(raw)=${_yawDeg.toStringAsFixed(1)}°  '
              'Heading=${_headingDeg.toStringAsFixed(1)}°\n'
              'Pitch=${_pitchDeg.toStringAsFixed(1)}°  '
              'Roll=${_rollDeg.toStringAsFixed(1)}°',
              style: const TextStyle(color: Colors.cyanAccent, fontSize: 12.5),
            ),
            const SizedBox(height: 6),

            // FPS/Hz (실제값 기반)
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Camera: ${_cameraFps.toStringAsFixed(1)} FPS',
                  style: const TextStyle(
                    color: Colors.greenAccent,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  'Sensor: ${_sensorHz.toStringAsFixed(1)} Hz',
                  style: const TextStyle(
                    color: Colors.orangeAccent,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  'UI: ${_uiTickMs}ms',
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
