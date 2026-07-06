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
    '😀',
    '😂',
    '😍',
    '👍',
    '🙏',
    '🔥',
    '🎉',
    '⚡',
    '🍔',
    '☕',
    '⚽',
    '📚',
    '🎮',
    '🐕',
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

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.roomTitle),
        backgroundColor: Colors.green,
      ),
      body: Column(
        children: [
          Expanded(
            child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: _chatService.messagesStream(widget.roomId),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Center(child: Text('오류가 발생했습니다: ${snapshot.error}'));
                }

                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }

                final messages = snapshot.data!.docs;

                if (messages.isEmpty) {
                  return const Center(
                    child: Text(
                      '첫 메시지를 보내보세요!',
                      style: TextStyle(color: Colors.black54),
                    ),
                  );
                }

                WidgetsBinding.instance.addPostFrameCallback((_) {
                  _chatService.markAsRead(widget.roomId);
                });

                return ListView.builder(
                  reverse: true,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  itemCount: messages.length,
                  itemBuilder: (context, index) {
                    final data = messages[index].data();

                    final isMe = data['senderId'] == uid;
                    final text = data['text'] ?? '';
                    final senderName = data['senderName'] ?? '익명';
                    final type = data['type'] ?? 'text';

                    return Align(
                      alignment: isMe
                          ? Alignment.centerRight
                          : Alignment.centerLeft,
                      child: Container(
                        constraints: BoxConstraints(
                          maxWidth: MediaQuery.of(context).size.width * 0.72,
                        ),
                        margin: const EdgeInsets.only(bottom: 10),
                        child: Column(
                          crossAxisAlignment: isMe
                              ? CrossAxisAlignment.end
                              : CrossAxisAlignment.start,
                          children: [
                            if (!isMe)
                              Padding(
                                padding: const EdgeInsets.only(
                                  left: 4,
                                  bottom: 3,
                                ),
                                child: Text(
                                  senderName,
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: Colors.black54,
                                  ),
                                ),
                              ),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 10,
                              ),
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
                    child: Center(
                      child: Text(emoji, style: const TextStyle(fontSize: 26)),
                    ),
                  );
                }).toList(),
              ),
            ),

          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
              child: Row(
                children: [
                  IconButton(
                    icon: Icon(
                      _showEmojiPanel
                          ? Icons.keyboard
                          : Icons.emoji_emotions_outlined,
                    ),
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
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 10,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                          borderSide: BorderSide.none,
                        ),
                      ),
                      onTap: () {
                        if (_showEmojiPanel) {
                          setState(() {
                            _showEmojiPanel = false;
                          });
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
          ),
        ],
      ),
    );
  }
}
