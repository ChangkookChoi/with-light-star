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
      backgroundColor: const Color(0xFF0A0E21), // 이미지가 없을 때 보일 배경색
      body: Stack(
        children: [
          // 1. 배경 이미지 (화면 꽉 채우기)
          SizedBox(
            width: double.infinity,
            height: double.infinity,
            child: Image.asset(
              'assets/images/splash_image.png',
              fit: BoxFit.cover,
              // [디버깅용] 이미지를 못 찾으면 에러 아이콘을 띄움
              errorBuilder: (context, error, stackTrace) {
                print("❌ 스플래시 이미지 로드 실패: $error");
                return Container(
                  color: const Color(0xFF0A0E21), // 실패 시 우주색 배경 유지
                  child: const Center(
                    child: Icon(Icons.broken_image,
                        color: Colors.white24, size: 50),
                  ),
                );
              },
            ),
          ),

          // 2. 가독성을 위한 반투명 오버레이
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
                // // 상단 여백 확보
                const Spacer(flex: 3),

                // // [복구됨] 앱 타이틀 (이게 빠져 있었습니다)
                // Text(
                //   "With Light Star",
                //   style: TextStyle(
                //     fontFamily: 'NanumGothic', // main.dart에 설정된 폰트
                //     fontSize: screenWidth * 0.09, // 화면 너비의 9%
                //     fontWeight: FontWeight.bold,
                //     color: Colors.white,
                //     letterSpacing: screenWidth * 0.005,
                //     shadows: [
                //       Shadow(
                //         blurRadius: screenWidth * 0.03,
                //         color: Colors.black.withOpacity(0.5),
                //         offset: const Offset(2.0, 2.0),
                //       ),
                //     ],
                //   ),
                // ),

                // 타이틀과 로딩바 사이 간격
                SizedBox(height: screenHeight * 0.04),

                // 로딩 인디케이터
                SizedBox(
                  width: screenWidth * 0.08,
                  height: screenWidth * 0.08,
                  child: CircularProgressIndicator(
                    color: Colors.amberAccent,
                    strokeWidth: screenWidth * 0.01,
                  ),
                ),

                const Spacer(flex: 2), // 하단 여백
              ],
            ),
          ),

          // 4. 하단 카피라이트 문구
          Positioned(
            bottom: screenHeight * 0.05,
            left: 0,
            right: 0,
            child: Text(
              "빛으로 그리는 나만의 별자리",
              textAlign: TextAlign.center,
              style: TextStyle(
                  color: Colors.white70,
                  fontSize: screenWidth * 0.035,
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
