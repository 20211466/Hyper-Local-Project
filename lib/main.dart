import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';
import 'views/main_shell.dart'; // 새로 만든 쉘을 불러옵니다.

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  runApp(MaterialApp(
    debugShowCheckedModeBanner: false,
    title: 'Hyper-Local',
    theme: ThemeData(
      primarySwatch: Colors.green,
      useMaterial3: true, // 최신 UI 스타일 적용
    ),
    home: const MainShell(), // 입구를 MainShell로 변경합니다.
  ));
}