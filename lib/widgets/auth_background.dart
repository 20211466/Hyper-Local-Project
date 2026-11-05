import 'package:flutter/material.dart';

/// 로그인/회원가입 화면에서 공통으로 쓰는 다크 테마 배경.
/// 팀 발표자료 표지(짙은 네이비 + 동심원 + 오렌지 포인트)와 톤을 맞췄습니다.
class AuthBackground extends StatelessWidget {
  final Widget child;
  const AuthBackground({super.key, required this.child});

  static const bg = Color(0xFF0B1120);
  static const panel = Color(0xFF161F32);
  static const panelBorder = Color(0xFF28334B);
  static const fieldFill = Color(0xFF1C2539);
  static const orange = Color(0xFFFF8A3D);
  static const teal = Color(0xFF2DD4BF);
  static const purple = Color(0xFF9B87F5);
  static const textSecondary = Color(0xFF8B96AD);

  @override
  Widget build(BuildContext context) {
    return Container(
      color: bg,
      child: Stack(
        children: [
          Positioned(top: -120, right: -80, child: _ring(320)),
          Positioned(top: -40, right: 10, child: _ring(200)),
          Positioned(bottom: -170, left: -110, child: _ring(320)),
          Positioned(bottom: -60, left: -20, child: _ring(180)),
          child,
        ],
      ),
    );
  }

  Widget _ring(double size) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white.withOpacity(0.06), width: 1),
      ),
    );
  }
}

InputDecoration authFieldDecoration({
  required String label,
  required IconData icon,
  String? hint,
}) {
  return InputDecoration(
    labelText: label,
    hintText: hint,
    labelStyle: const TextStyle(color: AuthBackground.textSecondary),
    hintStyle: TextStyle(color: AuthBackground.textSecondary.withOpacity(0.6)),
    prefixIcon: Icon(icon, color: AuthBackground.textSecondary),
    filled: true,
    fillColor: AuthBackground.fieldFill,
    contentPadding: const EdgeInsets.symmetric(vertical: 16),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: const BorderSide(color: AuthBackground.panelBorder),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: const BorderSide(color: AuthBackground.panelBorder),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: const BorderSide(color: AuthBackground.orange, width: 1.6),
    ),
    errorBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: const BorderSide(color: Colors.redAccent, width: 1.2),
    ),
    focusedErrorBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: const BorderSide(color: Colors.redAccent, width: 1.6),
    ),
  );
}
