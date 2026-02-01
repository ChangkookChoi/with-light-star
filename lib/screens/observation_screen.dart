import 'package:flutter/material.dart';
// [중요] ArkitCameraViewScreen이 있는 경로를 정확히 import 해주세요.
// 만약 lib/screens/ar/ 폴더 안에 있다면 경로를 맞춰주셔야 합니다.
import 'arkit_camera_view_screen.dart';

class MainObservationScreen extends StatefulWidget {
  const MainObservationScreen({Key? key}) : super(key: key);

  @override
  State<MainObservationScreen> createState() => _MainObservationScreenState();
}

class _MainObservationScreenState extends State<MainObservationScreen> {
  @override
  Widget build(BuildContext context) {
    // 기기의 화면 크기 정보 가져오기
    final double screenWidth = MediaQuery.of(context).size.width;
    final double screenHeight = MediaQuery.of(context).size.height;

    return Scaffold(
      extendBody: true,
      // 메인 AR 카메라 버튼 (중앙)
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
      floatingActionButton: FloatingActionButton(
        elevation: 4.0,
        backgroundColor: Colors.amberAccent,
        // [수정] 버튼 누르면 바로 AR 별자리 화면으로 이동
        onPressed: () => _navigateToARCamera(context),
        child: Icon(
          Icons.camera_enhance,
          color: const Color(0xFF0A0E21),
          size: screenWidth * 0.075,
        ),
      ),
      // 하단 네비게이션 바
      bottomNavigationBar: BottomAppBar(
        shape: const CircularNotchedRectangle(),
        notchMargin: 8.0,
        color: const Color(0xFF1B2735),
        child: Container(
          height: screenHeight * 0.08,
          padding: EdgeInsets.symmetric(horizontal: screenWidth * 0.05),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // 왼쪽 그룹: Home
              IconButton(
                icon: Icon(
                  Icons.home_filled,
                  color: Colors.amberAccent,
                  size: screenWidth * 0.07,
                ),
                onPressed: () {
                  // 현재 홈 화면이므로 새로고침하거나 비워둠
                },
              ),

              // 오른쪽 그룹: Storybook (추후 개발)
              IconButton(
                tooltip: '별자리 이야기',
                icon: Icon(
                  Icons.auto_stories,
                  color: Colors.white70,
                  size: screenWidth * 0.07,
                ),
                onPressed: () {
                  // TODO: AI 스토리 북 기능 연결
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('별자리 이야기 기능 준비 중입니다! 📚')),
                  );
                },
              ),
            ],
          ),
        ),
      ),
      body: Stack(
        children: [
          _buildBackground(),
          SafeArea(
            bottom: false,
            child: SingleChildScrollView(
              padding: EdgeInsets.only(bottom: screenHeight * 0.15),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildHeader(screenWidth),
                  SizedBox(height: screenHeight * 0.02),
                  _buildAstronomyGuide(screenWidth),
                  SizedBox(height: screenHeight * 0.03),
                  _buildBottomRecommendations(screenWidth, screenHeight),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ✅ [핵심] AR 카메라 화면으로 이동하는 함수
  void _navigateToARCamera(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(
        // 우리가 만든 ARKit 화면으로 연결
        builder: (context) => const ArkitCameraViewScreen(),
      ),
    );
  }

  Widget _buildBackground() {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF0A0E21), Color(0xFF1B2735)],
        ),
      ),
    );
  }

  Widget _buildHeader(double screenWidth) {
    return Padding(
      padding: EdgeInsets.all(screenWidth * 0.06),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            "With Light Star", // 앱 이름으로 변경
            style: TextStyle(
              fontSize: screenWidth * 0.075,
              fontWeight: FontWeight.bold,
              letterSpacing: -1,
              fontFamily: 'Pretendard-Bold', // 폰트 적용 (없으면 기본)
            ),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.amberAccent.withOpacity(0.1),
              borderRadius: BorderRadius.circular(30),
              border: Border.all(color: Colors.amberAccent.withOpacity(0.4)),
            ),
            child: Text(
              "✨ 오늘 관측하기 아주 좋아요!",
              style: TextStyle(
                color: Colors.amberAccent,
                fontSize: screenWidth * 0.035,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAstronomyGuide(double screenWidth) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: screenWidth * 0.05),
      child: Container(
        padding: EdgeInsets.all(screenWidth * 0.06),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.06),
          borderRadius: BorderRadius.circular(28),
          border: Border.all(color: Colors.white.withOpacity(0.05)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.auto_awesome,
                    color: Colors.amberAccent, size: screenWidth * 0.05),
                const SizedBox(width: 8),
                Text(
                  "오늘 밤 관측 가이드",
                  style: TextStyle(
                    fontSize: screenWidth * 0.045,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            _guideItem(screenWidth, Icons.wb_twilight, "일몰 후 1시간 뒤 관측 권장"),
            _guideItem(
                screenWidth, Icons.water_drop_outlined, "낮은 습도로 인한 선명한 시계"),
            _guideItem(screenWidth, Icons.explore_outlined, "서쪽 하늘 목성 관측 가능"),
          ],
        ),
      ),
    );
  }

  Widget _guideItem(double screenWidth, IconData icon, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        children: [
          Icon(icon, size: screenWidth * 0.05, color: Colors.white54),
          const SizedBox(width: 12),
          Text(
            text,
            style: TextStyle(
              color: Colors.white70,
              fontSize: screenWidth * 0.035,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomRecommendations(double screenWidth, double screenHeight) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: EdgeInsets.symmetric(
              horizontal: screenWidth * 0.07, vertical: 16),
          child: Text(
            "지금 추천하는 별자리",
            style: TextStyle(
              fontSize: screenWidth * 0.045,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        SizedBox(
          height: screenHeight * 0.22,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: EdgeInsets.symmetric(horizontal: screenWidth * 0.05),
            children: [
              _buildStarCard(screenWidth, "오리온자리", "가시성 98%", "용맹한 사냥꾼"),
              _buildStarCard(screenWidth, "카시오페아", "가시성 92%", "북쪽 하늘의 여왕"),
              _buildStarCard(screenWidth, "큰곰자리", "가시성 85%", "길잡이 북두칠성"),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildStarCard(
      double screenWidth, String title, String visibility, String desc) {
    return Container(
      width: screenWidth * 0.42,
      margin: const EdgeInsets.only(right: 16),
      padding: EdgeInsets.all(screenWidth * 0.05),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.08),
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: Colors.white.withOpacity(0.1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: screenWidth * 0.045,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            visibility,
            style: TextStyle(
              color: Colors.amberAccent,
              fontSize: screenWidth * 0.03,
            ),
          ),
          const Spacer(),
          Text(
            desc,
            style: TextStyle(
              color: Colors.white54,
              fontSize: screenWidth * 0.03,
            ),
          ),
        ],
      ),
    );
  }
}
