// lib/screens/observation_screen.dart

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'package:intl/intl.dart';
// [중요] ArkitCameraViewScreen 경로 확인
import 'arkit_camera_view_screen.dart';

class MainObservationScreen extends StatefulWidget {
  const MainObservationScreen({Key? key}) : super(key: key);

  @override
  State<MainObservationScreen> createState() => _MainObservationScreenState();
}

class _MainObservationScreenState extends State<MainObservationScreen> {
  String _currentAddress = '위치를 찾는 중...';
  String _currentDate = '';

  @override
  void initState() {
    super.initState();
    _initDateTime();
    _getCurrentPosition();
  }

  void _initDateTime() {
    final now = DateTime.now();
    _currentDate = DateFormat('M월 d일 (E)', 'ko_KR').format(now);
  }

  Future<void> _getCurrentPosition() async {
    bool serviceEnabled;
    LocationPermission permission;

    serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      if (mounted) setState(() => _currentAddress = '위치 서비스 꺼짐');
      return;
    }

    permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        if (mounted) setState(() => _currentAddress = '위치 권한 거부됨');
        return;
      }
    }

    try {
      Position position = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high);
      _getAddressFromLatLng(position);
    } catch (e) {
      if (mounted) setState(() => _currentAddress = '위치 확인 실패');
    }
  }

  Future<void> _getAddressFromLatLng(Position position) async {
    try {
      List<Placemark> placemarks =
          await placemarkFromCoordinates(position.latitude, position.longitude);
      Placemark place = placemarks[0];

      if (mounted) {
        setState(() {
          _currentAddress =
              "${place.locality} ${place.subLocality ?? place.thoroughfare ?? ''}";
        });
      }
    } catch (e) {
      if (mounted) setState(() => _currentAddress = '주소 변환 실패');
    }
  }

  void _navigateToARCamera(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const ArkitCameraViewScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final double screenWidth = MediaQuery.of(context).size.width;
    final double screenHeight = MediaQuery.of(context).size.height;

    return Scaffold(
      backgroundColor: const Color(0xFF0A0E21),
      // [수정] BottomAppBar 제거하고, 버튼을 플로팅 타입으로 변경
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
      floatingActionButton: Container(
        margin: const EdgeInsets.only(bottom: 20), // 하단에서 띄움
        height: 65, // 버튼 높이
        width: 200, // 버튼 너비 (넓게)
        child: FloatingActionButton.extended(
          elevation: 8.0,
          backgroundColor: Colors.amberAccent,
          onPressed: () => _navigateToARCamera(context),
          // 아이콘과 텍스트를 함께 배치하여 직관적으로 변경
          icon: const Icon(Icons.camera_enhance,
              color: Color(0xFF0A0E21), size: 28),
          label: const Text(
            "AR 관측 시작",
            style: TextStyle(
              color: Color(0xFF0A0E21),
              fontSize: 18,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.2,
            ),
          ),
        ),
      ),

      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color(0xFF050511),
              Color(0xFF0A0E21),
              Color(0xFF151530),
            ],
          ),
        ),
        child: SafeArea(
          child: SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: screenWidth * 0.05),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(height: screenHeight * 0.02),

                  // 1. 상단 정보
                  _buildHeader(screenWidth),

                  SizedBox(height: screenHeight * 0.03),

                  // 2. 가이드 배너
                  _buildGuideBanner(screenWidth, screenHeight),

                  SizedBox(height: screenHeight * 0.04),

                  // 3. 추천 별자리 (타이틀)
                  Text(
                    "✨ 지금 추천하는 별자리",
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: screenWidth * 0.055,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.0,
                    ),
                  ),
                  SizedBox(height: screenHeight * 0.02),

                  // 4. 추천 별자리 리스트 (카드 사이즈 확대)
                  SizedBox(
                    height: screenHeight * 0.28, // [수정] 높이 증가 (22% -> 28%)
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      physics: const BouncingScrollPhysics(),
                      children: [
                        _buildStarCard(screenWidth, "오리온자리", "가시성 98%",
                            "용맹한 사냥꾼", "⭐⭐⭐⭐⭐"),
                        _buildStarCard(screenWidth, "큰개자리", "가시성 92%",
                            "북쪽 하늘의 여왕", "⭐⭐⭐⭐"),
                        _buildStarCard(screenWidth, "황소자리", "가시성 85%",
                            "붉은 눈 알데바란", "⭐⭐⭐⭐"),
                      ],
                    ),
                  ),

                  // 하단 버튼에 가려지지 않게 여백 추가
                  SizedBox(height: 120),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(double screenWidth) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          _currentDate,
          style: TextStyle(
            fontSize: screenWidth * 0.035,
            fontWeight: FontWeight.w500,
            color: Colors.white70,
          ),
        ),
        const SizedBox(height: 4),
        Row(
          children: [
            Icon(Icons.location_on,
                color: Colors.amberAccent, size: screenWidth * 0.05),
            const SizedBox(width: 6),
            Text(
              _currentAddress,
              style: TextStyle(
                fontSize: screenWidth * 0.06,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildGuideBanner(double width, double height) {
    return Container(
      width: width,
      padding: EdgeInsets.all(width * 0.05),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF283593), Color(0xFF4527A0)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF4527A0).withOpacity(0.4),
            blurRadius: 15,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Text("🔭", style: TextStyle(fontSize: 20)),
                    const SizedBox(width: 8),
                    Text(
                      "오늘 밤 관측 가이드",
                      style: TextStyle(
                        color: Colors.amberAccent,
                        fontWeight: FontWeight.bold,
                        fontSize: width * 0.04,
                      ),
                    ),
                  ],
                ),
                SizedBox(height: height * 0.015),
                Text(
                  "오늘 달은 '상현달'입니다.\n남쪽 하늘에 오리온자리가\n가장 밝게 빛나고 있어요!",
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: width * 0.04,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.nightlight_round,
              color: Colors.white,
              size: width * 0.1,
            ),
          )
        ],
      ),
    );
  }

  Widget _buildStarCard(double screenWidth, String title, String visibility,
      String desc, String rating) {
    return Container(
      width: screenWidth * 0.65, // [수정] 너비 대폭 확대 (38% -> 65%)
      margin: const EdgeInsets.only(right: 20), // 간격도 조금 넓힘
      padding: EdgeInsets.all(screenWidth * 0.06),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.08),
        borderRadius: BorderRadius.circular(24), // 모서리 둥글기 증가
        border: Border.all(color: Colors.white.withOpacity(0.1)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.2),
            blurRadius: 10,
            offset: const Offset(0, 4),
          )
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.amberAccent.withOpacity(0.2),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              visibility,
              style: TextStyle(
                color: Colors.amberAccent,
                fontSize: screenWidth * 0.03,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            title,
            style: TextStyle(
              color: Colors.white,
              fontSize: screenWidth * 0.06, // 폰트 사이즈 키움
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            desc,
            style: TextStyle(
              color: Colors.white70,
              fontSize: screenWidth * 0.035, // 설명 폰트도 키움
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          const Spacer(),
          Text(
            rating,
            style: TextStyle(fontSize: screenWidth * 0.035),
          ),
        ],
      ),
    );
  }
}
