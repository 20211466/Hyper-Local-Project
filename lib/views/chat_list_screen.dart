import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../services/chat_service.dart';
import 'chat_room_screen.dart';

class ChatListScreen extends StatelessWidget {
  ChatListScreen({super.key});

  final ChatService _chatService = ChatService();

  // 💡 [동시 삭제 로직] 채팅방을 지우면 모임 데이터에서도 내 ID를 삭제합니다!
  Future<void> _deleteAndLeaveMeeting(BuildContext context, String roomId) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    try {
      // 1. 채팅방에서 내 ID 삭제 (채팅 목록에서 사라짐)
      await _chatService.leaveRoom(roomId);

      // 2. 모임 데이터에서도 내 ID 삭제 및 인원수 1명 줄이기 (완벽한 동기화)
      await FirebaseFirestore.instance.collection('meetings').doc(roomId).update({
        'participants': FieldValue.arrayRemove([uid]),
        'currentParticipants': FieldValue.increment(-1),
      });

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('만료된 채팅방과 모임에서 정상적으로 나갔습니다.')),
        );
      }
    } catch (e) {
      print("채팅방 삭제 오류: $e");
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('삭제 처리 중 오류가 발생했습니다.')),
        );
      }
    }
  }

  // 💡 나가기 확인 팝업창
  void _showDeleteDialog(BuildContext context, String roomId) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('채팅방 삭제'),
        content: const Text('이 채팅방을 삭제하시겠습니까?\n(해당 모임의 참여 기록도 함께 취소됩니다.)'),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('취소', style: TextStyle(color: Colors.grey)),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _deleteAndLeaveMeeting(context, roomId);
            },
            child: const Text('삭제', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;

    if (uid == null) {
      return const Scaffold(body: Center(child: Text('로그인이 필요합니다.')));
    }

    return Scaffold(
      appBar: AppBar(title: const Text('채팅'), backgroundColor: Colors.green),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: _chatService.myChatRoomsStream(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24.0),
                child: SelectableText( 
                  '오류가 발생했습니다 (아래 링크를 복사하세요):\n\n${snapshot.error}',
                  style: const TextStyle(color: Colors.red, fontSize: 16),
                ),
              ),
            );
          }

          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final rooms = snapshot.data!.docs;

          if (rooms.isEmpty) {
            return const Center(
              child: Text(
                '아직 참여한 채팅방이 없어요.\n모임을 만들거나 참여하면 채팅방이 자동으로 생깁니다.',
                textAlign: TextAlign.center,
              ),
            );
          }

          final now = DateTime.now();

          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: rooms.length,
            separatorBuilder: (context, index) => const SizedBox(height: 10),
            itemBuilder: (context, index) {
              final room = rooms[index];
              final data = room.data();

              final unreadCounts = Map<String, dynamic>.from(
                data['unreadCounts'] ?? {},
              );
              final unread = (unreadCounts[uid] as num?)?.toInt() ?? 0;

              final title = data['title'] ?? '제목 없음';
              final category = data['category'] ?? '기타';
              final lastMessage = data['lastMessage'] ?? '아직 메시지가 없습니다.';

              // 💡 마감 시간(deadline) 체크 로직 추가
              bool isExpired = false;
              if (data['deadline'] != null) {
                final deadline = (data['deadline'] as Timestamp).toDate();
                if (now.isAfter(deadline)) {
                  isExpired = true;
                }
              }

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
                    // 💡 만료된 채팅방은 시각적으로 약간 회색빛을 띠게 처리
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
                      // 💡 만료된 방은 이모지도 흑백/흐리게 처리하여 직관성 상승
                      CircleAvatar(
                        backgroundColor: isExpired ? Colors.grey[300] : Colors.green[50],
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
                                      color: isExpired ? Colors.grey[700] : Colors.black,
                                    ),
                                  ),
                                ),
                                // 💡 만료된 방에는 [종료됨] 딱지 붙여주기
                                if (isExpired)
                                  Container(
                                    margin: const EdgeInsets.only(left: 6),
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: Colors.grey[400],
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: const Text(
                                      '종료',
                                      style: TextStyle(fontSize: 10, color: Colors.white, fontWeight: FontWeight.bold),
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
                                    : (unread > 0 ? Colors.black87 : Colors.black54),
                                fontWeight: unread > 0 ? FontWeight.w600 : FontWeight.normal,
                              ),
                            ),
                          ],
                        ),
                      ),
                      
                      // 우측 영역 (안 읽은 메시지 수 OR 삭제 버튼)
                      if (isExpired)
                        // 💡 만료된 채팅방은 안 읽은 메시지 대신 [나가기] 버튼 활성화!
                        IconButton(
                          icon: const Icon(Icons.exit_to_app, color: Colors.redAccent),
                          tooltip: '채팅방 나가기',
                          onPressed: () => _showDeleteDialog(context, room.id),
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