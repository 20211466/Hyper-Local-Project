import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
// 💡 [추가] 파이어베이스 데이터베이스(Firestore)를 사용하기 위해 임포트 추가
import 'package:cloud_firestore/cloud_firestore.dart';

class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  // 💡 데이터베이스 인스턴스 추가
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

  Future<UserCredential> signUpWithEmail({
    required String email,
    required String password,
    required String nickname,
  }) async {
    // 1. Firebase Auth로 이메일 계정 생성
    final credential = await _auth.createUserWithEmailAndPassword(
      email: email,
      password: password,
    );
    await credential.user?.updateDisplayName(nickname);
    await credential.user?.reload();

    // 💡 [추가] 2. 회원가입 완료 후 Firestore 'users' 컬렉션에 내 정보와 매너 볼트 0점 기록!
    if (credential.user != null) {
      await _firestore.collection('users').doc(credential.user!.uid).set({
        'uid': credential.user!.uid,
        'email': email,
        'displayName': nickname,
        'mannerVolt': 0, // 매너 볼트 기본값 설정!
        'createdAt': FieldValue.serverTimestamp(),
      });
    }

    return credential;
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
    
    // 💡 [추가] 2. 구글 로그인 시 처음 온 유저라면 Firestore에 매너 볼트 0점 방 만들어주기
    if (userCredential.user != null) {
      final userRef = _firestore.collection('users').doc(userCredential.user!.uid);
      final docSnapshot = await userRef.get();
      
      // DB에 문서가 없다면 (처음 구글 로그인하는 회원이라면)
      if (!docSnapshot.exists) {
        await userRef.set({
          'uid': userCredential.user!.uid,
          'email': userCredential.user!.email,
          'displayName': userCredential.user!.displayName ?? '구글 유저',
          'mannerVolt': 0, // 매너 볼트 기본값 설정!
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
      default:
        return '오류가 발생했습니다: ${e.message}';
    }
  }
}