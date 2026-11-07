
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'chat_service.dart';

class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  final GoogleSignIn _googleSignIn = GoogleSignIn(
    clientId: '154101026042-44deanqlktbm63g78ijqjm6cf7221q95.apps.googleusercontent.com',
  );

  User? get currentUser => _auth.currentUser;

  Stream<User?> get authStateChanges => _auth.authStateChanges();

  Future<UserCredential> signInWithEmail({
    required String email,
    required String password,
  }) {
    return _auth.signInWithEmailAndPassword(
      email: email,
      password: password,
    );
  }

  // 회원가입
  Future<UserCredential> signUpWithEmail({
    required String email,
    required String password,
    required String nickname,
    required String gender,
    required int age,
    required String mbti,
    List<String> preferredCategories = const [],
  }) async {
    // 1. Firebase Auth로 이메일 계정 생성
    final credential = await _auth.createUserWithEmailAndPassword(
      email: email,
      password: password,
    );

    await credential.user?.updateDisplayName(nickname);
    await credential.user?.reload();

    // 2. 실제 나이를 연령대로 변환
    String ageGroup = '${(age ~/ 10) * 10}대';

    // 3. Firestore users 컬렉션에 사용자 정보 저장
    if (credential.user != null) {
      await _firestore
          .collection('users')
          .doc(credential.user!.uid)
          .set({
        'uid': credential.user!.uid,
        'email': email,
        'displayName': nickname,
        'gender': gender,
        'age': age,
        'ageGroup': ageGroup,
        'mbti': mbti.toUpperCase(),

        // 선택한 관심 카테고리와 우선순위 저장
        'preferredCategories': List<String>.from(preferredCategories),

        'mannerVolt': 0,
        'createdAt': FieldValue.serverTimestamp(),
      });
    }

    // 4. 이메일 인증 메일 발송
    await credential.user?.sendEmailVerification();

    return credential;
  }

  // ===================== 본인인증 (이메일) =====================

  bool get isIdentityVerified {
    final user = _auth.currentUser;

    if (user == null) return false;

    return user.emailVerified || user.phoneNumber != null;
  }

  Future<void> reloadCurrentUser() async {
    await _auth.currentUser?.reload();
  }

  Future<void> sendEmailVerification() async {
    await _auth.currentUser?.sendEmailVerification();
  }

  // ===================== 본인인증 (휴대폰) =====================

  // 한국 전화번호를 국제 표준 형식으로 변환
  String toE164PhoneNumber(String raw) {
    final digitsOnly = raw.replaceAll(RegExp(r'[^0-9]'), '');

    if (digitsOnly.startsWith('0')) {
      return '+82${digitsOnly.substring(1)}';
    }

    if (raw.trim().startsWith('+')) {
      return raw.trim();
    }

    return '+82$digitsOnly';
  }

  // 휴대폰 인증번호 발송
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

  // 사용자가 입력한 인증번호 확인
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

  // 휴대폰 인증 정보를 기존 계정에 연결
  Future<void> _linkPhoneCredential(
    PhoneAuthCredential credential,
  ) async {
    final user = _auth.currentUser;

    if (user == null) return;

    if (user.phoneNumber != null) return;

    await user.linkWithCredential(credential);
    await user.reload();

    // Firestore에도 인증된 번호 저장
    await _firestore.collection('users').doc(user.uid).set({
      'phoneNumber': _auth.currentUser?.phoneNumber,
      'phoneVerifiedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  // ===================== Google 로그인 =====================

  Future<UserCredential?> signInWithGoogle() async {
    final googleUser = await _googleSignIn.signIn();

    if (googleUser == null) return null;

    final googleAuth = await googleUser.authentication;

    final credential = GoogleAuthProvider.credential(
      accessToken: googleAuth.accessToken,
      idToken: googleAuth.idToken,
    );

    // 1. Firebase Google 로그인
    final userCredential = await _auth.signInWithCredential(
      credential,
    );

    // 2. 신규 Google 회원 Firestore 문서 생성
    if (userCredential.user != null) {
      final userRef = _firestore
          .collection('users')
          .doc(userCredential.user!.uid);

      final docSnapshot = await userRef.get();

      if (!docSnapshot.exists) {
        await userRef.set({
          'uid': userCredential.user!.uid,
          'email': userCredential.user!.email,
          'displayName':
              userCredential.user!.displayName ?? '구글 유저',
          'gender': '비공개',
          'age': 0,
          'ageGroup': '비공개',
          'mbti': '비공개',

          // Google 신규 가입자는 관심 카테고리 미설정 상태
          'preferredCategories': <String>[],

          'mannerVolt': 0,
          'createdAt': FieldValue.serverTimestamp(),
        });
      }
    }

    return userCredential;
  }

  // ===================== 로그아웃 =====================

  Future<void> signOut() async {
    await _googleSignIn.signOut();
    await _auth.signOut();
  }

  // ===================== 회원 탈퇴 =====================

  // Google 계정 여부 확인
  bool get isGoogleAccount {
    final user = _auth.currentUser;

    if (user == null) return false;

    return user.providerData.any(
      (p) => p.providerId == 'google.com',
    );
  }

  // 재인증
  Future<void> reauthenticate({String? password}) async {
    final user = _auth.currentUser;

    if (user == null) return;

    if (isGoogleAccount) {
      final googleUser = await _googleSignIn.signIn();

      if (googleUser == null) {
        throw FirebaseAuthException(
          code: 'reauth-cancelled',
          message: '재인증이 취소되었습니다.',
        );
      }

      final googleAuth = await googleUser.authentication;

      final credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      await user.reauthenticateWithCredential(credential);
    } else {
      if (password == null || password.isEmpty) {
        throw FirebaseAuthException(
          code: 'reauth-password-required',
          message: '비밀번호를 입력해주세요.',
        );
      }

      final credential = EmailAuthProvider.credential(
        email: user.email!,
        password: password,
      );

      await user.reauthenticateWithCredential(credential);
    }
  }

  // 회원 탈퇴
  Future<void> deleteAccount() async {
    final user = _auth.currentUser;

    if (user == null) return;

    final uid = user.uid;
    final chatService = ChatService();

    // 1. 내가 만든 모임 삭제
    final createdMeetings = await _firestore
        .collection('meetings')
        .where('creatorId', isEqualTo: uid)
        .get();

    for (final doc in createdMeetings.docs) {
      await doc.reference.delete();

      try {
        await chatService.leaveRoom(doc.id);
      } catch (_) {}
    }

    // 2. 참여 중인 다른 모임에서 나가기
    final joinedMeetings = await _firestore
        .collection('meetings')
        .where('participants', arrayContains: uid)
        .get();

    for (final doc in joinedMeetings.docs) {
      if (doc.data()['creatorId'] == uid) continue;

      await doc.reference.update({
        'participants': FieldValue.arrayRemove([uid]),
        'currentParticipants': FieldValue.increment(-1),
      });

      try {
        await chatService.leaveRoom(doc.id);
      } catch (_) {}
    }

    // 3. Firestore 사용자 정보 삭제
    try {
      await _firestore.collection('users').doc(uid).delete();
    } catch (_) {}

    // 4. Firebase Auth 계정 삭제
    await user.delete();

    // 5. Google 로그인 세션 정리
    try {
      await _googleSignIn.signOut();
    } catch (_) {}
  }

  // ===================== 오류 메시지 =====================

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

      case 'reauth-cancelled':
        return '재인증이 취소되었습니다.';

      case 'reauth-password-required':
        return '비밀번호를 입력해주세요.';

      default:
        return '오류가 발생했습니다: ${e.message}';
    }
  }
}
