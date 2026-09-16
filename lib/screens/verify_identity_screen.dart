import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import '../views/main_shell.dart';

/// 로그인은 했지만 아직 "본인인증"(이메일 인증 또는 휴대폰 인증)을 마치지 않은
/// 사용자에게 보여주는 화면입니다. 둘 중 하나만 완료하면 앱을 계속 사용할 수 있습니다.
class VerifyIdentityScreen extends StatefulWidget {
  const VerifyIdentityScreen({super.key});

  @override
  State<VerifyIdentityScreen> createState() => _VerifyIdentityScreenState();
}

class _VerifyIdentityScreenState extends State<VerifyIdentityScreen> {
  final _authService = AuthService();

  // 이메일 인증 상태
  bool _isSendingEmail = false;
  bool _isCheckingEmail = false;
  int _resendCooldown = 0;
  Timer? _cooldownTimer;
  String? _emailMessage;

  // 휴대폰 인증 상태
  final _phoneController = TextEditingController();
  final _codeController = TextEditingController();
  String? _verificationId;
  bool _isSendingCode = false;
  bool _isConfirmingCode = false;
  String? _phoneMessage;

  @override
  void dispose() {
    _cooldownTimer?.cancel();
    _phoneController.dispose();
    _codeController.dispose();
    super.dispose();
  }

  void _goToApp() {
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const MainShell()),
      (route) => false,
    );
  }

  void _startCooldown() {
    setState(() => _resendCooldown = 60);
    _cooldownTimer?.cancel();
    _cooldownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_resendCooldown <= 1) {
        timer.cancel();
        setState(() => _resendCooldown = 0);
      } else {
        setState(() => _resendCooldown -= 1);
      }
    });
  }

  Future<void> _resendEmail() async {
    setState(() {
      _isSendingEmail = true;
      _emailMessage = null;
    });
    try {
      await _authService.sendEmailVerification();
      setState(() => _emailMessage = '인증 메일을 다시 보냈어요. 메일함(스팸함 포함)을 확인해주세요.');
      _startCooldown();
    } on FirebaseAuthException catch (e) {
      setState(() => _emailMessage = _authService.messageFor(e));
    } finally {
      if (mounted) setState(() => _isSendingEmail = false);
    }
  }

  Future<void> _checkEmailVerified() async {
    setState(() {
      _isCheckingEmail = true;
      _emailMessage = null;
    });
    await _authService.reloadCurrentUser();
    if (_authService.isIdentityVerified) {
      _goToApp();
      return;
    }
    setState(() {
      _isCheckingEmail = false;
      _emailMessage = '아직 인증이 확인되지 않았어요. 메일의 인증 링크를 먼저 눌러주세요.';
    });
  }

  Future<void> _sendPhoneCode() async {
    if (_phoneController.text.trim().isEmpty) {
      setState(() => _phoneMessage = '휴대폰 번호를 입력해주세요.');
      return;
    }
    setState(() {
      _isSendingCode = true;
      _phoneMessage = null;
    });
    try {
      await _authService.startPhoneVerification(
        phoneNumber: _phoneController.text.trim(),
        onCodeSent: (verificationId) {
          if (!mounted) return;
          setState(() {
            _verificationId = verificationId;
            _isSendingCode = false;
            _phoneMessage = '인증번호를 보냈어요. 문자로 받은 6자리 번호를 입력해주세요.';
          });
        },
        onFailed: (e) {
          if (!mounted) return;
          setState(() {
            _isSendingCode = false;
            _phoneMessage = _authService.messageFor(e);
          });
        },
        onAutoVerified: () {
          // 안드로이드 기기가 SMS를 자동으로 인식한 경우
          if (!mounted) return;
          _goToApp();
        },
      );
    } catch (e) {
      setState(() {
        _isSendingCode = false;
        _phoneMessage = '인증번호 발송에 실패했습니다: $e';
      });
    }
  }

  Future<void> _confirmPhoneCode() async {
    if (_verificationId == null) return;
    if (_codeController.text.trim().isEmpty) {
      setState(() => _phoneMessage = '인증번호를 입력해주세요.');
      return;
    }
    setState(() {
      _isConfirmingCode = true;
      _phoneMessage = null;
    });
    try {
      await _authService.confirmPhoneCode(
        verificationId: _verificationId!,
        smsCode: _codeController.text.trim(),
      );
      _goToApp();
    } on FirebaseAuthException catch (e) {
      setState(() => _phoneMessage = _authService.messageFor(e));
    } finally {
      if (mounted) setState(() => _isConfirmingCode = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    return Scaffold(
      appBar: AppBar(
        title: const Text('본인인증'),
        automaticallyImplyLeading: false,
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: '로그아웃',
            onPressed: () => AuthService().signOut(),
          ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Icon(Icons.verified_user_outlined, color: Colors.green, size: 56),
              const SizedBox(height: 12),
              const Text(
                '안전한 동네 모임을 위해\n본인인증이 한 번 필요해요',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 6),
              const Text(
                '아래 중 하나만 완료하면 바로 이용할 수 있어요.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.black54),
              ),
              const SizedBox(height: 28),

              // ── 이메일 인증 카드 ──────────────────────────
              _SectionCard(
                icon: Icons.email_outlined,
                title: '이메일 인증',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      '${user?.email ?? ''} 주소로 인증 메일을 보냈어요.',
                      style: const TextStyle(color: Colors.black54),
                    ),
                    const SizedBox(height: 12),
                    if (_emailMessage != null) ...[
                      Text(_emailMessage!, style: const TextStyle(color: Colors.orange, fontSize: 13)),
                      const SizedBox(height: 8),
                    ],
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: (_isSendingEmail || _resendCooldown > 0) ? null : _resendEmail,
                            child: Text(
                              _resendCooldown > 0 ? '재전송 ($_resendCooldown초)' : '인증 메일 재전송',
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: ElevatedButton(
                            onPressed: _isCheckingEmail ? null : _checkEmailVerified,
                            style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white),
                            child: _isCheckingEmail
                                ? const SizedBox(
                                    width: 18, height: 18,
                                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                  )
                                : const Text('인증 완료 확인'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 16),
              const Row(
                children: [
                  Expanded(child: Divider()),
                  Padding(padding: EdgeInsets.symmetric(horizontal: 8), child: Text('또는', style: TextStyle(color: Colors.grey))),
                  Expanded(child: Divider()),
                ],
              ),
              const SizedBox(height: 16),

              // ── 휴대폰 인증 카드 ──────────────────────────
              _SectionCard(
                icon: Icons.smartphone_outlined,
                title: '휴대폰 번호 인증',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextField(
                      controller: _phoneController,
                      keyboardType: TextInputType.phone,
                      enabled: _verificationId == null,
                      decoration: const InputDecoration(
                        labelText: '휴대폰 번호',
                        hintText: '010-1234-5678',
                        prefixIcon: Icon(Icons.phone_outlined),
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 10),
                    if (_verificationId != null) ...[
                      TextField(
                        controller: _codeController,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: '인증번호 6자리',
                          prefixIcon: Icon(Icons.password_outlined),
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 10),
                    ],
                    if (_phoneMessage != null) ...[
                      Text(_phoneMessage!, style: const TextStyle(color: Colors.orange, fontSize: 13)),
                      const SizedBox(height: 8),
                    ],
                    SizedBox(
                      height: 46,
                      child: ElevatedButton(
                        onPressed: _verificationId == null
                            ? (_isSendingCode ? null : _sendPhoneCode)
                            : (_isConfirmingCode ? null : _confirmPhoneCode),
                        style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white),
                        child: (_isSendingCode || _isConfirmingCode)
                            ? const SizedBox(
                                width: 18, height: 18,
                                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                              )
                            : Text(_verificationId == null ? '인증번호 받기' : '인증하기'),
                      ),
                    ),
                    if (_verificationId != null)
                      TextButton(
                        onPressed: _isSendingCode ? null : () => setState(() { _verificationId = null; _codeController.clear(); }),
                        child: const Text('번호 다시 입력'),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final Widget child;

  const _SectionCard({required this.icon, required this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 8, offset: Offset(0, 3))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(icon, color: Colors.green),
              const SizedBox(width: 8),
              Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            ],
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}
