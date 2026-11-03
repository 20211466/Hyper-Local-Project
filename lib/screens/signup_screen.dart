import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import '../widgets/auth_background.dart';

class SignupScreen extends StatefulWidget {
  const SignupScreen({super.key});

  @override
  State<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends State<SignupScreen> {
  final _formKey = GlobalKey<FormState>();
  final _authService = AuthService();

  final _nicknameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _passwordConfirmController = TextEditingController();
  final _ageController = TextEditingController();

  String _selectedGender = '남성';
  String? _selectedMbti;

  bool _isLoading = false;
  String? _errorMessage;

  final List<String> _mbtiList = [
    'ISTJ', 'ISFJ', 'INFJ', 'INTJ',
    'ISTP', 'ISFP', 'INFP', 'INTP',
    'ESTP', 'ESFP', 'ENFP', 'ENTP',
    'ESTJ', 'ESFJ', 'ENFJ', 'ENTJ',
  ];

  @override
  void dispose() {
    _nicknameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _passwordConfirmController.dispose();
    _ageController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    if (_selectedMbti == null) {
      setState(() => _errorMessage = 'MBTI를 선택해주세요.');
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      await _authService.signUpWithEmail(
        email: _emailController.text.trim(),
        password: _passwordController.text,
        nickname: _nicknameController.text.trim(),
        gender: _selectedGender,
        age: int.parse(_ageController.text.trim()),
        mbti: _selectedMbti!,
      );
      // 회원가입 성공 시 자동 로그인되며, MainShell이 화면을 전환합니다.
      if (mounted) Navigator.of(context).pop();
    } on FirebaseAuthException catch (e) {
      setState(() => _errorMessage = _authService.messageFor(e));
    } catch (e) {
      setState(() => _errorMessage = '회원가입 중 오류가 발생했습니다: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Widget _sectionLabel(String text) {
    return Text(
      text,
      style: const TextStyle(
        color: AuthBackground.textSecondary,
        fontSize: 13,
        fontWeight: FontWeight.bold,
        letterSpacing: 0.3,
      ),
    );
  }

  Widget _genderChip(String label, String emoji, Color accent) {
    final selected = _selectedGender == label;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _selectedGender = label),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
            color: selected ? accent.withOpacity(0.15) : AuthBackground.fieldFill,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: selected ? accent : AuthBackground.panelBorder, width: 1.4),
          ),
          child: Column(
            children: [
              Text(emoji, style: const TextStyle(fontSize: 20)),
              const SizedBox(height: 4),
              Text(
                label,
                style: TextStyle(
                  color: selected ? accent : AuthBackground.textSecondary,
                  fontWeight: selected ? FontWeight.bold : FontWeight.normal,
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AuthBackground.bg,
      appBar: AppBar(
        backgroundColor: AuthBackground.bg,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        title: const Text('회원가입', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
      ),
      body: AuthBackground(
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: AuthBackground.panel,
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(color: AuthBackground.panelBorder),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _sectionLabel('계정 정보'),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _nicknameController,
                          style: const TextStyle(color: Colors.white),
                          decoration: authFieldDecoration(label: '닉네임', icon: Icons.person_outline),
                          validator: (value) {
                            if (value == null || value.trim().isEmpty) {
                              return '닉네임을 입력해주세요.';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _emailController,
                          style: const TextStyle(color: Colors.white),
                          keyboardType: TextInputType.emailAddress,
                          decoration: authFieldDecoration(label: '이메일', icon: Icons.email_outlined),
                          validator: (value) {
                            if (value == null || !value.contains('@')) {
                              return '올바른 이메일을 입력해주세요.';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _passwordController,
                          style: const TextStyle(color: Colors.white),
                          obscureText: true,
                          decoration: authFieldDecoration(label: '비밀번호 (6자 이상)', icon: Icons.lock_outline),
                          validator: (value) {
                            if (value == null || value.length < 6) {
                              return '비밀번호는 6자 이상이어야 합니다.';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _passwordConfirmController,
                          style: const TextStyle(color: Colors.white),
                          obscureText: true,
                          decoration: authFieldDecoration(label: '비밀번호 확인', icon: Icons.lock_outline),
                          validator: (value) {
                            if (value != _passwordController.text) {
                              return '비밀번호가 일치하지 않습니다.';
                            }
                            return null;
                          },
                        ),

                        const SizedBox(height: 24),
                        Divider(color: AuthBackground.panelBorder),
                        const SizedBox(height: 16),

                        _sectionLabel('프로필 정보'),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _ageController,
                          style: const TextStyle(color: Colors.white),
                          keyboardType: TextInputType.number,
                          decoration: authFieldDecoration(
                            label: '실제 나이 (예: 25)',
                            icon: Icons.cake_outlined,
                            hint: '앱에서는 20대 등으로만 표시됩니다.',
                          ),
                          validator: (value) {
                            if (value == null || value.trim().isEmpty) return '나이를 입력해주세요.';
                            if (int.tryParse(value.trim()) == null) return '숫자만 입력 가능합니다.';
                            return null;
                          },
                        ),
                        const SizedBox(height: 16),

                        _sectionLabel('성별'),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            _genderChip('남성', '👨', AuthBackground.teal),
                            const SizedBox(width: 12),
                            _genderChip('여성', '👩', AuthBackground.purple),
                          ],
                        ),
                        const SizedBox(height: 16),

                        _sectionLabel('MBTI'),
                        const SizedBox(height: 8),
                        DropdownButtonFormField<String>(
                          dropdownColor: AuthBackground.panel,
                          style: const TextStyle(color: Colors.white),
                          decoration: authFieldDecoration(label: 'MBTI 선택', icon: Icons.psychology_outlined),
                          value: _selectedMbti,
                          items: _mbtiList.map((mbti) {
                            return DropdownMenuItem(value: mbti, child: Text(mbti));
                          }).toList(),
                          onChanged: (value) {
                            setState(() {
                              _selectedMbti = value;
                              if (_errorMessage == 'MBTI를 선택해주세요.') _errorMessage = null;
                            });
                          },
                        ),

                        if (_errorMessage != null) ...[
                          const SizedBox(height: 16),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                            decoration: BoxDecoration(
                              color: Colors.redAccent.withOpacity(0.12),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.error_outline, color: Colors.redAccent, size: 18),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    _errorMessage!,
                                    style: const TextStyle(color: Colors.redAccent, fontSize: 13),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],

                        const SizedBox(height: 22),
                        SizedBox(
                          height: 52,
                          child: ElevatedButton(
                            onPressed: _isLoading ? null : _submit,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AuthBackground.orange,
                              foregroundColor: Colors.white,
                              elevation: 0,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                            ),
                            child: _isLoading
                                ? const SizedBox(
                                    width: 22,
                                    height: 22,
                                    child: CircularProgressIndicator(
                                      color: Colors.white,
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Text('회원가입', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
