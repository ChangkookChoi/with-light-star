import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:sensors_plus/sensors_plus.dart';

class RealHorizonScreen extends StatefulWidget {
  const RealHorizonScreen({super.key});

  @override
  State<RealHorizonScreen> createState() => _RealHorizonScreenState();
}

class _RealHorizonScreenState extends State<RealHorizonScreen> {
  CameraController? _controller;
  StreamSubscription? _accelerometerSub;

  // 필터링된 최종 값
  double _filteredPitch = 0.0;
  double _filteredRoll = 0.0;

  // 부드러움 조절 계수 (0.0 ~ 1.0)
  // 값이 작을수록 더 부드럽지만 반응이 약간 느려지고, 클수록 반응은 빠르지만 떨림이 생깁니다.
  static const double _filterFactor = 0.15;

  // 카메라 수직 화각 (일반적인 폰 기준)
  static const double _vFovDeg = 48.0;

  @override
  void initState() {
    super.initState();
    _initCamera();
    _initSensors();
  }

  void _initSensors() {
    _accelerometerSub = accelerometerEvents.listen((AccelerometerEvent event) {
      // 1. 현재 프레임의 Raw 값 계산
      double rawRoll = math.atan2(event.x, event.y) * 180 / math.pi;
      double rawPitch = math.atan2(
              -event.z, math.sqrt(event.x * event.x + event.y * event.y)) *
          180 /
          math.pi;

      if (!mounted) return;

      setState(() {
        // 2. 저주파 필터(Low-pass Filter) 적용
        // 공식: NewValue = (OldValue * (1 - α)) + (RawValue * α)
        _filteredPitch = (_filteredPitch * (1.0 - _filterFactor)) +
            (rawPitch * _filterFactor);
        _filteredRoll =
            (_filteredRoll * (1.0 - _filterFactor)) + (rawRoll * _filterFactor);
      });
    });
  }

  Future<void> _initCamera() async {
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) return;
      _controller = CameraController(cameras.first, ResolutionPreset.high,
          enableAudio: false);
      await _controller!.initialize();
      if (mounted) setState(() {});
    } catch (e) {
      debugPrint("Camera Error: $e");
    }
  }

  @override
  void dispose() {
    _accelerometerSub?.cancel();
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_controller == null || !_controller!.value.isInitialized) {
      return const Scaffold(
          backgroundColor: Colors.black,
          body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      body: Stack(
        children: [
          // 카메라 프리뷰
          SizedBox.expand(child: CameraPreview(_controller!)),

          // 천구 투영 기반 지평선 (필터링된 값 사용)
          CustomPaint(
            size: MediaQuery.of(context).size,
            painter: CelestialHorizonPainter(
              currentPitch: _filteredPitch,
              currentRoll: _filteredRoll,
              vFov: _vFovDeg,
            ),
          ),

          // 상단 상태바 레이아웃 (반투명 패널)
          Positioned(
            top: 60,
            left: 20,
            right: 20,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.black45,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    "PITCH: ${_filteredPitch.toStringAsFixed(1)}° | ROLL: ${_filteredRoll.toStringAsFixed(1)}°",
                    style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 12),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close, color: Colors.white, size: 28),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
          ),

          // 중앙 가이드 십자선 (참고용)
          Center(
            child: Container(
              width: 20,
              height: 20,
              decoration: BoxDecoration(
                border: Border.all(color: Colors.white24, width: 1),
                shape: BoxShape.circle,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class CelestialHorizonPainter extends CustomPainter {
  final double currentPitch;
  final double currentRoll;
  final double vFov;

  CelestialHorizonPainter({
    required this.currentPitch,
    required this.currentRoll,
    required this.vFov,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);

    // 1. 투영 계산: 지평선(0도)과 현재 카메라 Pitch의 차이
    // dy는 화면 중심에서 수직으로 떨어진 픽셀 거리
    final double dy = (currentPitch / vFov) * size.height;

    final paint = Paint()
      ..color = Colors.orangeAccent.withOpacity(0.8)
      ..strokeWidth = 3.0
      ..style = PaintingStyle.stroke;

    canvas.save();

    // 2. 화면 중심으로 이동 후 Roll 상쇄 회전
    canvas.translate(center.dx, center.dy);
    canvas.rotate(-currentRoll * math.pi / 180.0);

    // 3. 지평선 그리기
    // dy만큼 오프셋을 준 수평선 (화면 너비보다 훨씬 길게 그리기)
    canvas.drawLine(
        Offset(-size.width * 2, -dy), Offset(size.width * 2, -dy), paint);

    // 지평선 중앙 마커
    canvas.drawCircle(Offset(0, -dy), 10, paint);

    // 방위 표시용 짧은 수직선 (지평선 중앙 기준)
    canvas.drawLine(Offset(0, -dy - 10), Offset(0, -dy + 10), paint);

    canvas.restore();
  }

  @override
  bool shouldRepaint(CelestialHorizonPainter oldDelegate) =>
      oldDelegate.currentPitch != currentPitch ||
      oldDelegate.currentRoll != currentRoll;
}
