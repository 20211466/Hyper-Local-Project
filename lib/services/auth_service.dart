import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  
  final GoogleSignIn _googleSignIn = GoogleSignIn(
    clientId: '154101026042-44deanqlktbm63g78ijqjm6cf7221q95.apps.googleusercontent.com'
  );

  User? get currentUser => _auth.currentUser;

  Stream<User?> get authStateChanges => _auth.authStateChanges();

  Future<UserCredential> signInWithEmail({
    required String email,
    required String password,
  }) {
    return _auth.signInWithEmailAndPassword(email: email, password: password);
  }

  // 💡 [핵심 수정] 회원가입 시 성별, 나이, MBTI를 추가로 받습니다.
  Future<UserCredential> signUpWithEmail({
    required String email,
    required String password,
    required String nickname,
    required String gender, // 추가: '남성' 또는 '여성'
    required int age,       // 추가: 실제 나이 (예: 24)
    required String mbti,   // 추가: MBTI (예: 'ENFP')
  }) async {
    // 1. Firebase Auth로 이메일 계정 생성
    final credential = await _auth.createUserWithEmailAndPassword(
      email: email,
      password: password,
    );
    await credential.user?.updateDisplayName(nickname);
    await credential.user?.reload();

    // 💡 [개인정보 보호 로직] 실제 나이를 '20대', '30대' 형태로 변환합니다.
    // 예: 24 ~/ 10 = 2 -> 2 * 10 = 20 -> '20대'
    String ageGroup = '${(age ~/ 10) * 10}대';

    // 2. 가입 완료 후 Firestore 'users' 컬렉션에 정보 저장
    if (credential.user != null) {
      await _firestore.collection('users').doc(credential.user!.uid).set({
        'uid': credential.user!.uid,
        'email': email,
        'displayName': nickname,
        'gender': gender,         // 성별
        'age': age,               // 실제 나이 (내부 관리용)
        'ageGroup': ageGroup,     // 앱 화면에 표시될 나이대 ('20대', '30대')
        'mbti': mbti.toUpperCase(), // 소문자로 입력해도 대문자로 저장
        'mannerVolt': 0,          // 매너 볼트 기본값 설정!
        'createdAt': FieldValue.serverTimestamp(),
      });
    }

    // 💡 [본인인증] 이메일/비밀번호 가입 직후 인증 메일을 바로 발송합니다.
    await credential.user?.sendEmailVerification();

    return credential;
  }

  // ===================== 본인인증 (이메일) =====================

  /// 현재 로그인된 유저가 이메일 인증(또는 휴대폰 인증)을 마쳤는지 여부.
  /// Google 로그인 유저는 Firebase가 자동으로 emailVerified = true 로 표시해줍니다.
  bool get isIdentityVerified {
    final user = _auth.currentUser;
    if (user == null) return false;
    return user.emailVerified || user.phoneNumber != null;
  }

  /// 서버에 저장된 최신 인증 상태를 다시 받아옵니다. (인증 메일 클릭 직후 등 확인용)
  Future<void> reloadCurrentUser() async {
    await _auth.currentUser?.reload();
  }

  /// 인증 메일을 재전송합니다. 너무 자주 요청하면 FirebaseAuthException('too-many-requests')이 발생합니다.
  Future<void> sendEmailVerification() async {
    await _auth.currentUser?.sendEmailVerification();
  }

  // ===================== 본인인증 (휴대폰) =====================

  /// 한국 휴대폰 번호("010-1234-5678", "01012345678")를 국제 표준 형식("+8210...")으로 변환합니다.
  String toE164PhoneNumber(String raw) {
    final digitsOnly = raw.replaceAll(RegExp(r'[^0-9]'), '');
    if (digitsOnly.startsWith('0')) {
      return '+82${digitsOnly.substring(1)}';
    }
    if (raw.trim().startsWith('+')) return raw.trim();
    return '+82$digitsOnly';
  }

  /// 입력한 휴대폰 번호로 인증번호(SMS)를 발송합니다.
  /// 안드로이드에서는 기기가 SMS를 자동으로 인식하면 [onAutoVerified]가 바로 호출될 수 있습니다.
  Future<void> startPhoneVerification({
    required String phoneNumber,
    required void Function(String verificationId) onCodeSent,
    required void Function(FirebaseAuthException e) onFailed,
    required void Function() onAutoVerified,
  }) async {
    await _auth.verifyPhoneNumber(
      phoneNumber: toE164PhoneNumber(phoneNumber),
      timeout: const Duration(seconds: 60),
      verificationCompleted: (PhoneAuthCredential credential) async {
        await _linkPhoneCredential(credential);
        onAutoVerified();
      },
      verificationFailed: onFailed,
      codeSent: (String verificationId, int? resendToken) {
        onCodeSent(verificationId);
      },
      codeAutoRetrievalTimeout: (String verificationId) {},
    );
  }

  /// 사용자가 입력한 인증번호(SMS 코드)로 휴대폰 인증을 완료합니다.
  Future<void> confirmPhoneCode({
    required String verificationId,
    required String smsCode,
  }) async {
    final credential = PhoneAuthProvider.credential(
      verificationId: verificationId,
      smsCode: smsCode,
    );
    await _linkPhoneCredential(credential);
  }

  Future<void> _linkPhoneCredential(PhoneAuthCredential credential) async {
    final user = _auth.currentUser;
    if (user == null) return;

    // 이미 이 계정에 휴대폰 인증이 되어 있다면 다시 연결할 필요 없음
    if (user.phoneNumber != null) return;

    await user.linkWithCredential(credential);
    await user.reload();

    // 💡 Firestore에도 인증된 휴대폰 번호를 기록해 둡니다.
    await _firestore.collection('users').doc(user.uid).set({
      'phoneNumber': _auth.currentUser?.phoneNumber,
      'phoneVerifiedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<UserCredential?> signInWithGoogle() async {
    final googleUser = await _googleSignIn.signIn();
    if (googleUser == null) return null; // 사용자가 로그인 창을 취소함

    final googleAuth = await googleUser.authentication;
    final credential = GoogleAuthProvider.credential(
      accessToken: googleAuth.accessToken,
      idToken: googleAuth.idToken,
    );
    
    // 1. 구글 자격증명으로 Firebase Auth 로그인
    final userCredential = await _auth.signInWithCredential(credential);
    
    // 2. 구글 로그인 시 처음 온 유저라면 Firestore에 임시 방 만들어주기
    if (userCredential.user != null) {
      final userRef = _firestore.collection('users').doc(userCredential.user!.uid);
      final docSnapshot = await userRef.get();
      
      // DB에 문서가 없다면 (처음 구글 로그인하는 회원이라면 기본값/비공개 세팅)
      if (!docSnapshot.exists) {
        await userRef.set({
          'uid': userCredential.user!.uid,
          'email': userCredential.user!.email,
          'displayName': userCredential.user!.displayName ?? '구글 유저',
          'gender': '비공개',
          'age': 0,
          'ageGroup': '비공개',
          'mbti': '비공개',
          'mannerVolt': 0, 
          'createdAt': FieldValue.serverTimestamp(),
        });
      }
    }

    return userCredential;
  }

  Future<void> signOut() async {
    await _googleSignIn.signOut();
    await _auth.signOut();
  }

  String messageFor(FirebaseAuthException e) {
    switch (e.code) {
      case 'user-not-found':
        return '등록되지 않은 이메일입니다.';
      case 'wrong-password':
      case 'invalid-credential':
        return '이메일 또는 비밀번호가 올바르지 않습니다.';
      case 'email-already-in-use':
        return '이미 사용 중인 이메일입니다.';
      case 'weak-password':
        return '비밀번호는 6자 이상이어야 합니다.';
      case 'invalid-email':
        return '올바르지 않은 이메일 형식입니다.';
      case 'too-many-requests':
        return '요청이 너무 많습니다. 잠시 후 다시 시도해주세요.';
      case 'invalid-phone-number':
        return '올바르지 않은 휴대폰 번호 형식입니다.';
      case 'invalid-verification-code':
        return '인증번호가 올바르지 않습니다.';
      case 'credential-already-in-use':
      case 'provider-already-linked':
        return '이미 다른 계정에 연결된 휴대폰 번호입니다.';
      default:
        return '오류가 발생했습니다: ${e.message}';
    }
  }
}