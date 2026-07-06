import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class ChatService {
  ChatService({FirebaseFirestore? firestore, FirebaseAuth? auth})
    : _firestore = firestore ?? FirebaseFirestore.instance,
      _auth = auth ?? FirebaseAuth.instance;

  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;

  String? get currentUid => _auth.currentUser?.uid;

  CollectionReference<Map<String, dynamic>> get _chatRooms =>
      _firestore.collection('chatRooms');

  Future<void> createRoomForMeeting({
    required String meetingId,
    required Map<String, dynamic> meetingData,
  }) async {
    final user = _auth.currentUser;
    if (user == null) return;

    final participants = List<String>.from(
      meetingData['participants'] ?? [user.uid],
    );

    if (!participants.contains(user.uid)) {
      participants.add(user.uid);
    }

    await _chatRooms.doc(meetingId).set({
      'meetingId': meetingId,
      'title': meetingData['title'] ?? '제목 없음',
      'category': meetingData['category'] ?? '기타',
      'members': participants,
      'createdBy': meetingData['creatorId'] ?? user.uid,
      'createdAt': FieldValue.serverTimestamp(),
      'lastMessage': '채팅방이 생성되었습니다.',
      'lastMessageAt': FieldValue.serverTimestamp(),
      'lastSenderId': '',
      'unreadCounts': {for (final uid in participants) uid: 0},
    }, SetOptions(merge: true));
  }

  Future<void> joinRoom({
    required String meetingId,
    required Map<String, dynamic> meetingData,
  }) async {
    final user = _auth.currentUser;
    if (user == null) return;

    final roomRef = _chatRooms.doc(meetingId);
    final roomSnap = await roomRef.get();

    if (!roomSnap.exists) {
      await createRoomForMeeting(
        meetingId: meetingId,
        meetingData: meetingData,
      );
    }

    await roomRef.set({
      'meetingId': meetingId,
      'title': meetingData['title'] ?? '제목 없음',
      'category': meetingData['category'] ?? '기타',
      'members': FieldValue.arrayUnion([user.uid]),
      'unreadCounts.${user.uid}': 0,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> leaveRoom(String meetingId) async {
    final uid = currentUid;
    if (uid == null) return;

    await _chatRooms.doc(meetingId).update({
      'members': FieldValue.arrayRemove([uid]),
      'unreadCounts.$uid': FieldValue.delete(),
    });
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> myChatRoomsStream() {
    final uid = currentUid;
    if (uid == null) return const Stream.empty();

    return _chatRooms
        .where('members', arrayContains: uid)
        .orderBy('lastMessageAt', descending: true)
        .snapshots();
  }

  Stream<int> totalUnreadCountStream() {
    final uid = currentUid;
    if (uid == null) return Stream.value(0);

    return myChatRoomsStream().map((snapshot) {
      int total = 0;

      for (final doc in snapshot.docs) {
        final data = doc.data();
        final unreadCounts = Map<String, dynamic>.from(
          data['unreadCounts'] ?? {},
        );
        total += (unreadCounts[uid] as num?)?.toInt() ?? 0;
      }

      return total;
    });
  }

  Future<void> markAsRead(String roomId) async {
    final uid = currentUid;
    if (uid == null) return;

    await _chatRooms.doc(roomId).set({
      'unreadCounts.$uid': 0,
    }, SetOptions(merge: true));
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> messagesStream(String roomId) {
    return _chatRooms
        .doc(roomId)
        .collection('messages')
        .orderBy('createdAt', descending: true)
        .snapshots();
  }

  Future<void> sendMessage({
    required String roomId,
    required String text,
    String type = 'text',
  }) async {
    final user = _auth.currentUser;
    final trimmed = text.trim();

    if (user == null || trimmed.isEmpty) return;

    final roomRef = _chatRooms.doc(roomId);
    final messageRef = roomRef.collection('messages').doc();

    await _firestore.runTransaction((transaction) async {
      final roomSnap = await transaction.get(roomRef);
      final roomData = roomSnap.data() ?? <String, dynamic>{};
      final members = List<String>.from(roomData['members'] ?? []);

      transaction.set(messageRef, {
        'senderId': user.uid,
        'senderName': user.displayName ?? user.email ?? '익명',
        'senderPhotoUrl': user.photoURL,
        'text': trimmed,
        'type': type,
        'createdAt': FieldValue.serverTimestamp(),
      });

      final updateData = <String, dynamic>{
        'lastMessage': trimmed,
        'lastMessageAt': FieldValue.serverTimestamp(),
        'lastSenderId': user.uid,
      };

      for (final memberUid in members) {
        if (memberUid != user.uid) {
          updateData['unreadCounts.$memberUid'] = FieldValue.increment(1);
        }
      }

      updateData['unreadCounts.${user.uid}'] = 0;

      transaction.set(roomRef, updateData, SetOptions(merge: true));
    });
  }
}
