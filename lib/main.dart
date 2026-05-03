import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';

// 🚀 경로 수정: views 폴더 안에 있는 파일을 불러오도록 변경했습니다.
import 'views/map_screen.dart'; 

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // 파이어베이스 초기화
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  runApp(const MaterialApp(
    debugShowCheckedModeBanner: false,
    // 이제 views/map_screen.dart의 MapScreen을 정상적으로 인식합니다.
    home: MapScreen(), 
  ));
}