import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// 모임(meetings)과 채팅방(chatRooms)을 같은 meetingId로 연결하는 서비스입니다.
/// 채팅방의 멤버 정보는 항상 meetings 문서의 실제 participants를 기준으로 확인합니다.
class ChatService {
  ChatService({FirebaseFirestore? firestore, FirebaseAuth? auth})
    : _firestore = firestore ?? FirebaseFirestore.instance,
      _auth = auth ?? FirebaseAuth.instance;

  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;

  String? get currentUid => _auth.currentUser?.uid;

  CollectionReference<Map<String, dynamic>> get _chatRooms =>
      _firestore.collection('chatRooms');

  CollectionReference<Map<String, dynamic>> get _meetings =>
      _firestore.collection('meetings');

  /// 모임 생성자가 최초 채팅방을 만들거나 누락된 채팅방을 복구합니다.
  Future<void> createRoomForMeeting({
    required String meetingId,
    required Map<String, dynamic> meetingData,
  }) async {
    await _ensureRoomMembership(
      meetingId: meetingId,
      fallbackData: meetingData,
    );
  }

  /// 모임 참가자를 기존 채팅방에 추가합니다.
  Future<void> joinRoom({
    required String meetingId,
    required Map<String, dynamic> meetingData,
  }) async {
    await _ensureRoomMembership(
      meetingId: meetingId,
      fallbackData: meetingData,
    );
  }

  /// 전달받은 오래된 데이터보다 Firestore의 최신 모임 문서를 우선 사용합니다.
  /// 모임 참가 저장이 끝난 뒤 호출해야 합니다.
  Future<void> _ensureRoomMembership({
    required String meetingId,
    required Map<String, dynamic> fallbackData,
  }) async {
    final user = _auth.currentUser;
    if (user == null) {
      throw StateError('로그인이 필요합니다. 다시 로그인한 후 시도해 주세요.');
    }
    if (meetingId.trim().isEmpty) {
      throw ArgumentError.value(meetingId, 'meetingId', '모임 ID가 비어 있습니다.');
    }

    final uid = user.uid;
    final meetingRef = _meetings.doc(meetingId);
    final roomRef = _chatRooms.doc(meetingId);

    await _firestore.runTransaction((transaction) async {
      // 트랜잭션은 모든 문서를 먼저 읽은 다음 쓰기를 시작합니다.
      final meetingSnapshot = await transaction.get(meetingRef);
      if (!meetingSnapshot.exists) {
        throw StateError('모임 정보를 찾을 수 없습니다. 모임이 삭제되었을 수 있습니다.');
      }
      final meetingData = meetingSnapshot.data() ?? fallbackData;
      final creatorId = (meetingData['creatorId'] ?? '').toString();
      final rawParticipants = meetingData['participants'];
      final participants = <String>{};

      if (rawParticipants is Iterable) {
        for (final value in rawParticipants) {
          final memberId = value?.toString().trim() ?? '';
          if (memberId.isNotEmpty) participants.add(memberId);
        }
      }
      if (creatorId.isNotEmpty) participants.add(creatorId);

      // 모임 방장 또는 participants 배열에 등록된 사용자만 채팅방에 들어갈 수 있습니다.
      if (!participants.contains(uid)) {
        throw StateError('모임 참가자 정보에 현재 계정이 없습니다. 모임 참가가 먼저 저장됐는지 확인해 주세요.');
      }
      if (creatorId.isEmpty) {
        throw StateError('모임 방장 정보(creatorId)가 없어 채팅방을 연결할 수 없습니다.');
      }

      final roomSnapshot = await transaction.get(roomRef);
      final title = (meetingData['title'] ?? '제목 없음').toString();
      final category = (meetingData['category'] ?? '기타').toString();

      if (!roomSnapshot.exists) {
        // 채팅방 문서가 없으면 실제 모임 참가자 전체를 초기 멤버로 생성합니다.
        transaction.set(roomRef, {
          'meetingId': meetingId,
          'title': title,
          'category': category,
          'members': participants.toList(),
          'createdBy': creatorId,
          'createdAt': FieldValue.serverTimestamp(),
          'lastMessage': '채팅방이 생성되었습니다.',
          'lastMessageAt': FieldValue.serverTimestamp(),
          'lastSenderId': '',
          'unreadCounts': {for (final memberId in participants) memberId: 0},
          if (meetingData['deadline'] != null)
            'deadline': meetingData['deadline'],
          if (meetingData['expireAt'] != null)
            'expireAt': meetingData['expireAt'],
        });
        return;
      }

      final roomData = roomSnapshot.data() ?? <String, dynamic>{};
      // 이 계정만 추가합니다. 다른 사용자의 UID를 임의로 추가하지 않습니다.
      // Firestore 보안 규칙의 '본인 UID 1명 추가' 조건과 정확히 일치합니다.
      final updateData = <String, dynamic>{
        'meetingId': meetingId,
        'title': title,
        'category': category,
        'members': FieldValue.arrayUnion([uid]),
        'updatedAt': FieldValue.serverTimestamp(),
      };

      // 읽지 않은 메시지 개수 필드가 없거나 잘못된 형식인 기존 방을 안전하게 보정합니다.
      final rawUnreadCounts = roomData['unreadCounts'];
      if (rawUnreadCounts is Map) {
        final unreadCounts = Map<String, dynamic>.from(rawUnreadCounts);
        unreadCounts.putIfAbsent(uid, () => 0);
        if (unreadCounts.length != rawUnreadCounts.length ||
            !rawUnreadCounts.containsKey(uid)) {
          updateData['unreadCounts'] = unreadCounts;
        }
      } else {
        updateData['unreadCounts'] = {uid: 0};
      }

      // 중요: 기존 채팅방 갱신에서는 deadline/expireAt을 수정하지 않습니다.
      // 이전 Firestore 규칙에서는 이 두 필드가 허용 목록에 없어 참가자 추가까지 거부됐습니다.
      // 새 채팅방을 만들 때는 위에서 두 필드를 최초 저장합니다.
      transaction.update(roomRef, updateData);
    });
  }

  /// 로그인한 사용자가 참가 중인 모임의 누락된 채팅방 연결을 복구합니다.
  /// 채팅 탭 진입 시와 새로고침 시 호출합니다.
  Future<int> syncMyChatRoomsFromMeetings({String? userId}) async {
    final uid = userId ?? currentUid;
    if (uid == null) return 0;
    if (_auth.currentUser?.uid != uid) {
      throw StateError('로그인 계정이 변경되었습니다. 채팅 목록을 다시 열어 주세요.');
    }

    final results = await Future.wait([
      _meetings.where('participants', arrayContains: uid).get(),
      _meetings.where('creatorId', isEqualTo: uid).get(),
    ]);

    final meetingDocs = <String, QueryDocumentSnapshot<Map<String, dynamic>>>{};
    for (final result in results) {
      for (final doc in result.docs) {
        meetingDocs[doc.id] = doc;
      }
    }

    var syncedCount = 0;
    final failures = <String>[];
    for (final meetingDoc in meetingDocs.values) {
      if (_auth.currentUser?.uid != uid) break;
      try {
        await _ensureRoomMembership(
          meetingId: meetingDoc.id,
          fallbackData: meetingDoc.data(),
        );
        syncedCount++;
      } catch (error) {
        failures.add('${meetingDoc.id}: $error');
        // 한 채팅방 오류가 다른 모임의 채팅방 복구를 막지 않도록 계속 진행합니다.
        // ignore: avoid_print
        print('[채팅방 복구 실패] ${meetingDoc.id}: $error');
      }
    }

    if (failures.isNotEmpty) {
      throw StateError(
        '일부 채팅방을 연결하지 못했습니다. 실패 ${failures.length}개 / 확인 ${meetingDocs.length}개\n'
        '${failures.take(2).join('\n')}',
      );
    }
    return syncedCount;
  }

  Future<void> leaveRoom(String meetingId) async {
    final uid = currentUid;
    if (uid == null) throw StateError('로그인이 필요합니다.');

    await _chatRooms.doc(meetingId).update({
      'members': FieldValue.arrayRemove([uid]),
      'unreadCounts.$uid': FieldValue.delete(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  /// 특정 UID가 참가한 채팅방만 조회합니다.
  /// UID를 인자로 받으므로 계정 전환 후 이전 계정의 스트림을 재사용하지 않습니다.
  Stream<QuerySnapshot<Map<String, dynamic>>> chatRoomsStreamFor(String uid) {
    return _chatRooms.where('members', arrayContains: uid).snapshots();
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> myChatRoomsStream() {
    final uid = currentUid;
    if (uid == null) return const Stream.empty();
    return chatRoomsStreamFor(uid);
  }

  /// 하단 탭의 읽지 않은 개수도 로그인 계정이 바뀌면 새 UID로 자동 전환합니다.
  Stream<int> totalUnreadCountStream() {
    return _auth.authStateChanges().asyncExpand((user) {
      if (user == null) return Stream<int>.value(0);
      return chatRoomsStreamFor(user.uid).map((snapshot) {
        var total = 0;
        for (final doc in snapshot.docs) {
          final raw = doc.data()['unreadCounts'];
          final unreadCounts = raw is Map
              ? Map<String, dynamic>.from(raw)
              : <String, dynamic>{};
          total += (unreadCounts[user.uid] as num?)?.toInt() ?? 0;
        }
        return total;
      });
    });
  }

  Future<void> markAsRead(String roomId) async {
    final uid = currentUid;
    if (uid == null) throw StateError('로그인이 필요합니다.');
    await _chatRooms.doc(roomId).update({'unreadCounts.$uid': 0});
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
    if (user == null) throw StateError('로그인이 필요합니다.');
    if (trimmed.isEmpty) return;

    final roomRef = _chatRooms.doc(roomId);
    final messageRef = roomRef.collection('messages').doc();

    await _firestore.runTransaction((transaction) async {
      final roomSnapshot = await transaction.get(roomRef);
      if (!roomSnapshot.exists) {
        throw StateError('채팅방 문서가 없습니다. 모임에 다시 참여한 뒤 채팅 탭을 새로고침해 주세요.');
      }

      final roomData = roomSnapshot.data() ?? <String, dynamic>{};
      final rawMembers = roomData['members'];
      final members = rawMembers is Iterable
          ? rawMembers.map((value) => value.toString()).toSet()
          : <String>{};
      if (!members.contains(user.uid)) {
        throw StateError('현재 계정이 채팅방 참가자로 등록되지 않았습니다. 채팅 탭에서 새로고침해 주세요.');
      }

      final rawUnread = roomData['unreadCounts'];
      final unreadCounts = rawUnread is Map
          ? Map<String, dynamic>.from(rawUnread)
          : <String, dynamic>{};
      unreadCounts[user.uid] = 0;
      for (final memberUid in members) {
        if (memberUid != user.uid) {
          final oldValue = (unreadCounts[memberUid] as num?)?.toInt() ?? 0;
          unreadCounts[memberUid] = oldValue + 1;
        }
      }

      transaction.set(messageRef, {
        'senderId': user.uid,
        'senderName': user.displayName ?? user.email ?? '익명',
        'senderPhotoUrl': user.photoURL,
        'text': trimmed,
        'type': type,
        'createdAt': FieldValue.serverTimestamp(),
      });

      transaction.update(roomRef, {
        'lastMessage': trimmed,
        'lastMessageAt': FieldValue.serverTimestamp(),
        'lastSenderId': user.uid,
        'unreadCounts': unreadCounts,
      });
    });
  }
}
