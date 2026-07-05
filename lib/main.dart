import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart'; // 💡 추가: Firebase 인증 상태를 확인하기 위해 필요합니다.
import 'firebase_options.dart';

import 'views/main_shell.dart';
import 'screens/login_screen.dart'; // 💡 추가: 팀원이 만든 로그인 화면을 가져옵니다.

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  runApp(const MaterialApp(
    debugShowCheckedModeBanner: false,
    home: AuthGate(), // 💡 수정: MainShell() 대신 인증 상태를 확인하는 문지기(AuthGate)를 세웁니다.
  ));
}

// 💡 추가: 로그인 상태에 따라 알아서 화면을 바꿔주는 '문지기' 역할의 위젯입니다.
class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      // FirebaseAuth가 로그인/로그아웃 상태가 바뀔 때마다 알려줍니다.
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        // 1. 로그인 데이터가 있으면 (로그인 성공 상태) -> 원래 보려던 MainShell(지도 등) 화면으로 이동!
        if (snapshot.hasData) {
          return const MainShell(); 
        }
        
        // 2. 로그인 데이터가 없으면 (로그아웃 상태) -> 팀원이 만든 로그인 화면으로 이동!
        return const LoginScreen(); 
      },
    );
  }
}