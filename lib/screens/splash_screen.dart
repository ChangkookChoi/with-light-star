// lib/screens/splash_screen.dart

import 'dart:async';
import 'package:flutter/material.dart';
import 'observation_screen.dart'; // 메인 화면 import

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    // 2.5초 뒤에 메인 화면으로 이동
    Timer(const Duration(milliseconds: 2500), () {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => const MainObservationScreen()),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    // [반응형 핵심] 화면 크기 가져오기
    final Size screenSize = MediaQuery.of(context).size;
    final double screenWidth = screenSize.width;
    final double screenHeight = screenSize.height;

    return Scaffold(
      backgroundColor: const Color(0xFF0A0E21),
      body: Stack(
        children: [
          // 1. 배경 이미지 (화면 꽉 채우기)
          SizedBox(
            width: double.infinity,
            height: double.infinity,
            child: Image.asset(
              'assets/images/splash_image.png',
              fit: BoxFit.cover,
            ),
          ),

          // 2. 가독성을 위한 반투명 오버레이 (선택 사항)
          // 글씨가 잘 보이도록 배경을 살짝 어둡게 처리
          Container(
            width: double.infinity,
            height: double.infinity,
            color: Colors.black.withOpacity(0.3),
          ),

          // 3. 중앙 콘텐츠 (타이틀 + 로딩)
          Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // 상단 여백 확보 (비율)
                Spacer(flex: 3),

                // 타이틀과 로딩바 사이 간격 (화면 높이의 4%)
                SizedBox(height: screenHeight * 0.04),

                // 로딩 인디케이터
                SizedBox(
                  width: screenWidth * 0.08, // 너비의 8% 크기
                  height: screenWidth * 0.08,
                  child: CircularProgressIndicator(
                    color: Colors.amberAccent,
                    strokeWidth: screenWidth * 0.01, // 두께도 비율로 (너비의 1%)
                  ),
                ),

                Spacer(flex: 2), // 하단 여백 비율 조절
              ],
            ),
          ),

          // 4. 하단 카피라이트 문구
          Positioned(
            bottom: screenHeight * 0.05, // 하단에서 5% 떨어진 위치
            left: 0,
            right: 0,
            child: Text(
              "빛으로 그리는 나만의 별자리",
              textAlign: TextAlign.center,
              style: TextStyle(
                  color: Colors.white70,
                  fontSize: screenWidth * 0.035, // 화면 너비의 3.5% 크기
                  fontWeight: FontWeight.w300,
                  letterSpacing: 1.2,
                  shadows: [
                    Shadow(
                      blurRadius: 4.0,
                      color: Colors.black.withOpacity(0.5),
                    ),
                  ]),
            ),
          ),
        ],
      ),
    );
  }
}
