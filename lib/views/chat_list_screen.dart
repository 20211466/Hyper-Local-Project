import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../services/chat_service.dart';
import 'chat_room_screen.dart';

class ChatListScreen extends StatefulWidget {
  const ChatListScreen({super.key});

  @override
  State<ChatListScreen> createState() => _ChatListScreenState();
}

class _ChatListScreenState extends State<ChatListScreen> {
  final ChatService _chatService = ChatService();
  late Stream<QuerySnapshot<Map<String, dynamic>>> _roomsStream;
  StreamSubscription<User?>? _authSubscription;
  String? _currentUid;
  bool _isRepairing = false;

  @override
  void initState() {
    super.initState();
    _currentUid = FirebaseAuth.instance.currentUser?.uid;
    _roomsStream = _currentUid == null
        ? const Stream.empty()
        : _chatService.chatRoomsStreamFor(_currentUid!);

    // 로그아웃 후 다른 계정으로 로그인해도 이전 UID의 Firestore 스트림을 재사용하지 않습니다.
    _authSubscription = FirebaseAuth.instance.authStateChanges().listen(
      _handleAuthChanged,
    );

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _repairMissingRooms();
    });
  }

  void _handleAuthChanged(User? user) {
    final nextUid = user?.uid;
    if (nextUid == _currentUid || !mounted) return;

    setState(() {
      _currentUid = nextUid;
      _roomsStream = nextUid == null
          ? const Stream.empty()
          : _chatService.chatRoomsStreamFor(nextUid);
      _isRepairing = false;
    });

    if (nextUid != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _repairMissingRooms();
      });
    }
  }

  @override
  void dispose() {
    _authSubscription?.cancel();
    super.dispose();
  }

  Future<void> _repairMissingRooms() async {
    final uid = _currentUid;
    if (!mounted || _isRepairing || uid == null) return;
    setState(() => _isRepairing = true);
    try {
      final count = await _chatService.syncMyChatRoomsFromMeetings(userId: uid);
      debugPrint('[채팅방 확인] $count개 모임의 채팅방을 확인했습니다.');
    } catch (error, stackTrace) {
      debugPrint('[채팅방 동기화 오류] $error');
      debugPrintStack(stackTrace: stackTrace);
      if (mounted && _currentUid == uid) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('채팅방 연결을 완료하지 못했습니다. 다시 시도해 주세요.\n$error'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 5),
          ),
        );
      }
    } finally {
      if (mounted && _currentUid == uid) setState(() => _isRepairing = false);
    }
  }

  DateTime? _readDate(dynamic value) {
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    if (value is String) return DateTime.tryParse(value);
    return null;
  }

  Future<void> _deleteAndLeaveMeeting(
    BuildContext context,
    String roomId,
  ) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    try {
      final meetingRef = FirebaseFirestore.instance
          .collection('meetings')
          .doc(roomId);

      // 먼저 모임 참가자 정보에서 본인을 제거합니다.
      // 이후 채팅방 멤버에서도 제거하여 다음 동기화 때 다시 추가되지 않게 합니다.
      await FirebaseFirestore.instance.runTransaction((transaction) async {
        final meetingSnapshot = await transaction.get(meetingRef);
        if (!meetingSnapshot.exists) return;

        final data = meetingSnapshot.data() ?? <String, dynamic>{};
        final participants = List<String>.from(data['participants'] ?? []);
        if (!participants.contains(uid)) return;

        final currentCount =
            (data['currentParticipants'] as num?)?.toInt() ??
            participants.length;

        transaction.update(meetingRef, {
          'participants': FieldValue.arrayRemove([uid]),
          'currentParticipants': currentCount > 0 ? currentCount - 1 : 0,
        });
      });

      await _chatService.leaveRoom(roomId);

      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('채팅방과 모임에서 정상적으로 나갔습니다.')));
      }
    } catch (error) {
      debugPrint('[채팅방 나가기 오류] $error');
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('나가기 처리 중 오류가 발생했습니다: $error')));
      }
    }
  }

  void _showLeaveDialog(BuildContext context, String roomId) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('채팅방 나가기'),
        content: const Text('이 채팅방에서 나가면 해당 모임의 참여도 취소됩니다.'),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('취소', style: TextStyle(color: Colors.grey)),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(dialogContext);
              _deleteAndLeaveMeeting(context, roomId);
            },
            child: const Text(
              '나가기',
              style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final uid = _currentUid;

    if (uid == null) {
      return const Scaffold(body: Center(child: Text('로그인이 필요합니다.')));
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('채팅'),
        backgroundColor: Colors.green,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            tooltip: '채팅방 다시 불러오기',
            onPressed: _isRepairing ? null : _repairMissingRooms,
            icon: _isRepairing
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.refresh),
          ),
        ],
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: _roomsStream,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.error_outline,
                      color: Colors.red,
                      size: 42,
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      '채팅방을 불러오지 못했습니다.',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 17,
                      ),
                    ),
                    const SizedBox(height: 8),
                    SelectableText(
                      '${snapshot.error}',
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.red, fontSize: 12),
                    ),
                    const SizedBox(height: 14),
                    ElevatedButton.icon(
                      onPressed: _isRepairing ? null : _repairMissingRooms,
                      icon: const Icon(Icons.refresh),
                      label: const Text('채팅방 다시 확인'),
                    ),
                  ],
                ),
              ),
            );
          }

          if (snapshot.connectionState == ConnectionState.waiting &&
              !snapshot.hasData) {
            return const Center(
              child: CircularProgressIndicator(color: Colors.green),
            );
          }

          final rooms =
              snapshot.data?.docs.toList() ??
              <QueryDocumentSnapshot<Map<String, dynamic>>>[];

          // 서버 orderBy를 제거했으므로 마지막 메시지 시간을 화면에서 정렬합니다.
          rooms.sort((a, b) {
            final aDate =
                _readDate(a.data()['lastMessageAt']) ??
                DateTime.fromMillisecondsSinceEpoch(0);
            final bDate =
                _readDate(b.data()['lastMessageAt']) ??
                DateTime.fromMillisecondsSinceEpoch(0);
            return bDate.compareTo(aDate);
          });

          if (rooms.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.chat_bubble_outline,
                      size: 48,
                      color: Colors.grey,
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      '아직 참여한 채팅방이 없어요.\n모임을 만들거나 참여하면 채팅방이 연결됩니다.',
                      textAlign: TextAlign.center,
                      style: TextStyle(height: 1.5),
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: _isRepairing ? null : _repairMissingRooms,
                      icon: const Icon(Icons.refresh),
                      label: const Text('내 모임 채팅방 다시 확인'),
                    ),
                  ],
                ),
              ),
            );
          }

          final now = DateTime.now();
          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: rooms.length,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (context, index) {
              final room = rooms[index];
              final data = room.data();
              final unreadCounts = Map<String, dynamic>.from(
                data['unreadCounts'] ?? <String, dynamic>{},
              );
              final unread = (unreadCounts[uid] as num?)?.toInt() ?? 0;
              final title = (data['title'] ?? '제목 없음').toString();
              final category = (data['category'] ?? '기타').toString();
              final lastMessage = (data['lastMessage'] ?? '아직 메시지가 없습니다.')
                  .toString();
              final deadline = _readDate(data['deadline']);
              final isExpired = deadline != null && now.isAfter(deadline);

              return InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) =>
                          ChatRoomScreen(roomId: room.id, roomTitle: title),
                    ),
                  );
                },
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: isExpired ? Colors.grey[200] : Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: const [
                      BoxShadow(
                        color: Colors.black12,
                        blurRadius: 8,
                        offset: Offset(0, 3),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      CircleAvatar(
                        backgroundColor: isExpired
                            ? Colors.grey[300]
                            : Colors.green[50],
                        child: Text(
                          _emojiForCategory(category),
                          style: TextStyle(
                            color: isExpired ? Colors.grey : Colors.black,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    title,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 16,
                                      color: isExpired
                                          ? Colors.grey[700]
                                          : Colors.black,
                                    ),
                                  ),
                                ),
                                if (isExpired)
                                  Container(
                                    margin: const EdgeInsets.only(left: 6),
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 6,
                                      vertical: 2,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Colors.grey[400],
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: const Text(
                                      '종료',
                                      style: TextStyle(
                                        fontSize: 10,
                                        color: Colors.white,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Text(
                              lastMessage,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: isExpired
                                    ? Colors.grey[500]
                                    : (unread > 0
                                          ? Colors.black87
                                          : Colors.black54),
                                fontWeight: unread > 0
                                    ? FontWeight.w600
                                    : FontWeight.normal,
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (isExpired)
                        IconButton(
                          icon: const Icon(
                            Icons.exit_to_app,
                            color: Colors.redAccent,
                          ),
                          tooltip: '채팅방 나가기',
                          onPressed: () => _showLeaveDialog(context, room.id),
                        )
                      else if (unread > 0)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.red,
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            unread > 99 ? '99+' : '$unread',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }

  String _emojiForCategory(String category) {
    switch (category) {
      case '식사':
        return '🍔';
      case '운동':
        return '⚽';
      case '공부':
        return '📚';
      case '게임':
        return '🎮';
      case '산책':
        return '🐕';
      default:
        return '⚡';
    }
  }
}
