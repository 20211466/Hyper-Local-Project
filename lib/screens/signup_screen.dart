import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../services/auth_service.dart';

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
  
  // 💡 [추가] 나이 입력 컨트롤러
  final _ageController = TextEditingController();

  // 💡 [추가] 선택형 데이터 상태 관리
  String _selectedGender = '남성';
  String? _selectedMbti;
  
  bool _isLoading = false;
  String? _errorMessage;

  // 💡 [추가] MBTI 16가지 리스트
  final List<String> _mbtiList = [
    'ISTJ', 'ISFJ', 'INFJ', 'INTJ',
    'ISTP', 'ISFP', 'INFP', 'INTP',
    'ESTP', 'ESFP', 'ENFP', 'ENTP',
    'ESTJ', 'ESFJ', 'ENFJ', 'ENTJ'
  ];

  @override
  void dispose() {
    _nicknameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _passwordConfirmController.dispose();
    _ageController.dispose(); // 💡 메모리 누수 방지
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    
    // 💡 [추가] MBTI 선택 유효성 검사
    if (_selectedMbti == null) {
      setState(() => _errorMessage = 'MBTI를 선택해주세요.');
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    
    try {
      // 💡 [수정] 성별, 나이, MBTI 파라미터 추가 전달
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('회원가입')),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextFormField(
                    controller: _nicknameController,
                    decoration: const InputDecoration(
                      labelText: '닉네임',
                      prefixIcon: Icon(Icons.person_outline),
                      border: OutlineInputBorder(),
                    ),
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
                    keyboardType: TextInputType.emailAddress,
                    decoration: const InputDecoration(
                      labelText: '이메일',
                      prefixIcon: Icon(Icons.email_outlined),
                      border: OutlineInputBorder(),
                    ),
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
                    obscureText: true,
                    decoration: const InputDecoration(
                      labelText: '비밀번호 (6자 이상)',
                      prefixIcon: Icon(Icons.lock_outline),
                      border: OutlineInputBorder(),
                    ),
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
                    obscureText: true,
                    decoration: const InputDecoration(
                      labelText: '비밀번호 확인',
                      prefixIcon: Icon(Icons.lock_outline),
                      border: OutlineInputBorder(),
                    ),
                    validator: (value) {
                      if (value != _passwordController.text) {
                        return '비밀번호가 일치하지 않습니다.';
                      }
                      return null;
                    },
                  ),
                  
                  const SizedBox(height: 24),
                  const Divider(),
                  const SizedBox(height: 16),
                  const Text('프로필 정보', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey)),
                  const SizedBox(height: 16),

                  // 💡 [추가] 1. 나이 입력란
                  TextFormField(
                    controller: _ageController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: '실제 나이 (예: 25)',
                      hintText: '앱에서는 20대 등으로만 표시됩니다.',
                      prefixIcon: Icon(Icons.cake_outlined),
                      border: OutlineInputBorder(),
                    ),
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) return '나이를 입력해주세요.';
                      if (int.tryParse(value.trim()) == null) return '숫자만 입력 가능합니다.';
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),

                  // 💡 [추가] 2. 성별 선택
                  const Text('성별', style: TextStyle(fontSize: 14)),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: ChoiceChip(
                          label: const Center(child: Text('👨 남성')),
                          selected: _selectedGender == '남성',
                          selectedColor: Colors.green[200],
                          onSelected: (selected) => setState(() => _selectedGender = '남성'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ChoiceChip(
                          label: const Center(child: Text('👩 여성')),
                          selected: _selectedGender == '여성',
                          selectedColor: Colors.green[200],
                          onSelected: (selected) => setState(() => _selectedGender = '여성'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // 💡 [추가] 3. MBTI 선택
                  DropdownButtonFormField<String>(
                    decoration: const InputDecoration(
                      labelText: 'MBTI',
                      prefixIcon: Icon(Icons.psychology_outlined),
                      border: OutlineInputBorder(),
                    ),
                    value: _selectedMbti,
                    items: _mbtiList.map((mbti) {
                      return DropdownMenuItem(value: mbti, child: Text(mbti));
                    }).toList(),
                    onChanged: (value) {
                      setState(() {
                        _selectedMbti = value;
                        if (_errorMessage == 'MBTI를 선택해주세요.') _errorMessage = null; // 에러 메시지 초기화
                      });
                    },
                  ),
                  
                  if (_errorMessage != null) ...[
                    const SizedBox(height: 24),
                    Text(
                      _errorMessage!,
                      style: const TextStyle(color: Colors.red),
                      textAlign: TextAlign.center,
                    ),
                  ],
                  
                  const SizedBox(height: 24),
                  
                  SizedBox(
                    height: 50,
                    child: ElevatedButton(
                      onPressed: _isLoading ? null : _submit,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                        foregroundColor: Colors.white,
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
                          : const Text('회원가입', style: TextStyle(fontSize: 16)),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}