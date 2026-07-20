import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../services/chat_service.dart';

class ChatRoomScreen extends StatefulWidget {
  final String roomId;
  final String roomTitle;

  const ChatRoomScreen({
    super.key,
    required this.roomId,
    required this.roomTitle,
  });

  @override
  State<ChatRoomScreen> createState() => _ChatRoomScreenState();
}

class _ChatRoomScreenState extends State<ChatRoomScreen> {
  final ChatService _chatService = ChatService();
  final TextEditingController _messageController = TextEditingController();

  bool _showEmojiPanel = false;

  final List<String> _emojis = const [
    '😀', '😂', '😍', '👍', '🙏', '🔥', '🎉',
    '⚡', '🍔', '☕', '⚽', '📚', '🎮', '🐕',
  ];

  @override
  void initState() {
    super.initState();
    _chatService.markAsRead(widget.roomId);
  }

  @override
  void dispose() {
    _messageController.dispose();
    super.dispose();
  }

  Future<void> _send({String type = 'text'}) async {
    final text = _messageController.text;
    if (text.trim().isEmpty) return;
    _messageController.clear();

    await _chatService.sendMessage(
      roomId: widget.roomId,
      text: text,
      type: type,
    );
    await _chatService.markAsRead(widget.roomId);
  }

  // 💡 [방법 A 핵심 로직] 채팅방 및 모임 동시 나가기 함수
  Future<void> _leaveChatAndMeeting() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    try {
      // 1. 채팅방에서 내 ID 삭제 (팀원분이 만든 함수 활용)
      await _chatService.leaveRoom(widget.roomId);

      // 2. 모임 데이터에서도 내 ID 삭제 및 참여 인원 1명 줄이기
      await FirebaseFirestore.instance.collection('meetings').doc(widget.roomId).update({
        'participants': FieldValue.arrayRemove([uid]),
        'currentParticipants': FieldValue.increment(-1),
      });

      // 3. 완료 후 화면 닫기 (팝업 닫기 -> 채팅방 닫기)
      if (mounted) {
        Navigator.pop(context); // 팝업 닫기
        Navigator.pop(context); // 채팅방 닫기
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('모임 참여가 취소되었습니다.')),
        );
      }
    } catch (e) {
      print("나가기 오류: $e");
    }
  }

  // 💡 나가기 확인 팝업창 띄우기
  void _showExitDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('모임 나가기'),
        content: const Text('채팅방을 나가면 해당 모임의 참여도 자동으로 취소됩니다. 정말 나가시겠습니까?'),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context), // 아니요 누르면 팝업만 닫힘
            child: const Text('아니요', style: TextStyle(color: Colors.grey)),
          ),
          TextButton(
            onPressed: _leaveChatAndMeeting, // 예 누르면 동시 삭제 로직 실행
            child: const Text('예', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.roomTitle),
        backgroundColor: Colors.green,
        actions: [
          // 💡 AppBar 우측 상단에 나가기 아이콘 추가
          IconButton(
            icon: const Icon(Icons.exit_to_app),
            tooltip: '나가기',
            onPressed: _showExitDialog,
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: _chatService.messagesStream(widget.roomId),
              builder: (context, snapshot) {
                if (snapshot.hasError) return Center(child: Text('오류: ${snapshot.error}'));
                if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());

                final messages = snapshot.data!.docs;
                if (messages.isEmpty) {
                  return const Center(
                    child: Text('첫 메시지를 보내보세요!', style: TextStyle(color: Colors.black54)),
                  );
                }

                WidgetsBinding.instance.addPostFrameCallback((_) {
                  _chatService.markAsRead(widget.roomId);
                });

                return ListView.builder(
                  reverse: true,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  itemCount: messages.length,
                  itemBuilder: (context, index) {
                    final data = messages[index].data();
                    final isMe = data['senderId'] == uid;
                    final text = data['text'] ?? '';
                    final senderName = data['senderName'] ?? '익명';
                    final type = data['type'] ?? 'text';

                    return Align(
                      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
                      child: Container(
                        constraints: BoxConstraints(
                          maxWidth: MediaQuery.of(context).size.width * 0.72,
                        ),
                        margin: const EdgeInsets.only(bottom: 10),
                        child: Column(
                          crossAxisAlignment: isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                          children: [
                            if (!isMe)
                              Padding(
                                padding: const EdgeInsets.only(left: 4, bottom: 3),
                                child: Text(senderName, style: const TextStyle(fontSize: 12, color: Colors.black54)),
                              ),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                              decoration: BoxDecoration(
                                color: isMe ? Colors.green : Colors.grey[200],
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: Text(
                                text,
                                style: TextStyle(
                                  color: isMe ? Colors.white : Colors.black87,
                                  fontSize: type == 'emoji' ? 28 : 15,
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
          ),
          
          if (_showEmojiPanel)
            Container(
              height: 96,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              color: Colors.grey[50],
              child: GridView.count(
                crossAxisCount: 7,
                childAspectRatio: 1.2,
                children: _emojis.map((emoji) {
                  return InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: () async {
                      _messageController.text = emoji;
                      await _send(type: 'emoji');
                    },
                    child: Center(child: Text(emoji, style: const TextStyle(fontSize: 26))),
                  );
                }).toList(),
              ),
            ),

          StreamBuilder<DocumentSnapshot>(
            stream: FirebaseFirestore.instance.collection('meetings').doc(widget.roomId).snapshots(),
            builder: (context, snapshot) {
              bool isExpired = false;
              if (snapshot.hasData && snapshot.data!.exists) {
                final data = snapshot.data!.data() as Map<String, dynamic>?;
                if (data != null && data['deadline'] != null) {
                  final deadline = (data['deadline'] as Timestamp).toDate();
                  if (DateTime.now().isAfter(deadline)) {
                    isExpired = true;
                  }
                }
              }

              if (isExpired) {
                return SafeArea(
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 20),
                    color: Colors.grey[200],
                    child: const Text(
                      '종료된 번개의 채팅방입니다. 더 이상 메시지를 보낼 수 없습니다.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.black54, fontWeight: FontWeight.bold, fontSize: 14),
                    ),
                  ),
                );
              }

              return SafeArea(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
                  child: Row(
                    children: [
                      IconButton(
                        icon: Icon(_showEmojiPanel ? Icons.keyboard : Icons.emoji_emotions_outlined),
                        color: Colors.green,
                        onPressed: () {
                          setState(() {
                            _showEmojiPanel = !_showEmojiPanel;
                          });
                        },
                      ),
                      Expanded(
                        child: TextField(
                          controller: _messageController,
                          minLines: 1,
                          maxLines: 4,
                          decoration: InputDecoration(
                            hintText: '메시지를 입력하세요',
                            filled: true,
                            fillColor: Colors.grey[100],
                            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(24),
                              borderSide: BorderSide.none,
                            ),
                          ),
                          onTap: () {
                            if (_showEmojiPanel) {
                              setState(() => _showEmojiPanel = false);
                            }
                          },
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.send),
                        color: Colors.green,
                        onPressed: _send,
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}