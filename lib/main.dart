import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart'; // 💡 추가: Firebase 인증 상태를 확인하기 위해 필요합니다.
import 'firebase_options.dart';

import 'views/main_shell.dart';
import 'screens/login_screen.dart'; // 💡 추가: 팀원이 만든 로그인 화면을 가져옵니다.
import 'screens/verify_identity_screen.dart'; // 💡 추가: 이메일/휴대폰 본인인증 화면

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
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }

        // 1. 로그인 데이터가 없으면 (로그아웃 상태) -> 팀원이 만든 로그인 화면으로 이동!
        if (!snapshot.hasData) {
          return const LoginScreen();
        }

        // 2. 로그인은 했지만 본인인증(이메일 인증 또는 휴대폰 인증)이 안 됐다면
        //    -> 본인인증 화면으로 이동! (Google 로그인 유저는 이메일이 이미 인증된 상태로 취급됩니다)
        return FutureBuilder<void>(
          future: FirebaseAuth.instance.currentUser?.reload(),
          builder: (context, reloadSnapshot) {
            if (reloadSnapshot.connectionState == ConnectionState.waiting) {
              return const Scaffold(body: Center(child: CircularProgressIndicator()));
            }

            final user = FirebaseAuth.instance.currentUser;
            final isVerified = (user?.emailVerified ?? false) || (user?.phoneNumber != null);

            if (!isVerified) {
              return const VerifyIdentityScreen();
            }

            // 3. 로그인 + 본인인증까지 완료 -> 원래 보려던 MainShell(지도 등) 화면으로 이동!
            return const MainShell();
          },
        );
      },
    );
  }
}