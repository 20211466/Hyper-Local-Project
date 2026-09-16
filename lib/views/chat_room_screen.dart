import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_generative_ai/google_generative_ai.dart'; 
import 'package:flutter_dotenv/flutter_dotenv.dart';

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
  
  // 💡 [추가] 차단한 유저들의 UID를 담아둘 리스트
  List<String> _blockedUsers = []; 

  final List<String> _emojis = const [
    '😀', '😂', '😍', '👍', '🙏', '🔥', '🎉',
    '⚡', '🍔', '☕', '⚽', '📚', '🎮', '🐕',
  ];

  @override
  void initState() {
    super.initState();
    _chatService.markAsRead(widget.roomId);
    _loadBlockedUsers(); // 💡 채팅방 열릴 때 내가 차단한 사람 목록 불러오기
  }

  // 💡 [추가] 내 차단 목록을 DB에서 가져오는 함수
  Future<void> _loadBlockedUsers() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    
    try {
      final doc = await FirebaseFirestore.instance.collection('users').doc(uid).get();
      final data = doc.data();
      if (data != null && data['blockedUsers'] != null) {
        setState(() {
          _blockedUsers = List<String>.from(data['blockedUsers']);
        });
      }
    } catch (e) {
      print("차단 목록 로드 오류: $e");
    }
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

  Future<void> _leaveChatAndMeeting() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    try {
      await _chatService.leaveRoom(widget.roomId);
      await FirebaseFirestore.instance.collection('meetings').doc(widget.roomId).update({
        'participants': FieldValue.arrayRemove([uid]),
        'currentParticipants': FieldValue.increment(-1),
      });

      if (mounted) {
        Navigator.pop(context); 
        Navigator.pop(context); 
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('모임 참여가 취소되었습니다.')),
        );
      }
    } catch (e) {
      print("나가기 오류: $e");
    }
  }

  void _showExitDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('모임 나가기'),
        content: const Text('채팅방을 나가면 해당 모임의 참여도 자동으로 취소됩니다. 정말 나가시겠습니까?'),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context), 
            child: const Text('아니요', style: TextStyle(color: Colors.grey)),
          ),
          TextButton(
            onPressed: _leaveChatAndMeeting, 
            child: const Text('예', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Future<void> _triggerIcebreaker(BuildContext context) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const AlertDialog(
        content: Row(
          children: [
            CircularProgressIndicator(color: Colors.orange),
            SizedBox(width: 20),
            Expanded(child: Text("AI 요정이 눈치를 보는 중... 💡", style: TextStyle(fontWeight: FontWeight.bold))),
          ],
        ),
      ),
    );

    try {
      final meetingDoc = await FirebaseFirestore.instance.collection('meetings').doc(widget.roomId).get();
      final meetingData = meetingDoc.data();
      if (meetingData == null) {
        if (context.mounted) {
          Navigator.pop(context);
          _showCustomDialog(context, "오류", "모임 정보를 불러올 수 없습니다.");
        }
        return;
      }
      
      final category = meetingData['category'] ?? '모임';
      final title = meetingData['title'] ?? '';
      final List<dynamic> participants = meetingData['participants'] ?? [];

      List<String> mbtiList = [];
      for (var uid in participants.take(5)) {
        try {
          final userDoc = await FirebaseFirestore.instance.collection('users').doc(uid).get();
          final mbti = (userDoc.data() as Map<String, dynamic>?)?['mbti'] ?? '비공개';
          if (mbti != '비공개') mbtiList.add(mbti);
        } catch (e) {
          print("MBTI 수집 실패(무시하고 진행): $e");
        }
      }

      final model = GenerativeModel(
        model: 'gemini-3.6-flash',
        apiKey: dotenv.env['GEMINI_API_KEY'] ?? '',
      );

      final prompt = """
      너는 동네 번개 모임 채팅방의 발랄한 'AI 요정'이야.
      채팅방에 정적이 흘러서 분위기를 띄워야 해! 참여자들의 MBTI 조합과 모임 주제를 보고, 다같이 대답하기 좋은 재미있는 첫 질문(아이스브레이킹)을 딱 1개만 던져줘.
      - 모임 주제: [$category] $title
      - 참여자 MBTI 조합: ${mbtiList.isNotEmpty ? mbtiList.join(', ') : '정보 없음'}
      
      규칙:
      1. 첫 문장은 "안녕하세요! AI 요정입니다 🧚✨" 로 고정해.
      2. MBTI 조합을 재치있게 언급해.
      3. 절대 3문장을 넘기지 말고 친근한 반말로 해줘.
      """;

      final response = await model.generateContent([Content.text(prompt)]).timeout(
        const Duration(seconds: 25),
      );
      
      final icebreakerText = response.text ?? '여러분, 오늘 저녁 메뉴로 뭐 드실 건가요? 😊';

      try {
        final roomRef = FirebaseFirestore.instance.collection('chatRooms').doc(widget.roomId);
        
        await roomRef.collection('messages').add({
          'text': icebreakerText,
          'senderId': 'ai_fairy',
          'senderName': '🧚 AI 요정',
          'createdAt': FieldValue.serverTimestamp(), 
          'type': 'text',
        });

        await roomRef.set({
          'lastMessage': icebreakerText,
          'lastMessageAt': FieldValue.serverTimestamp(),
          'lastSenderId': 'ai_fairy',
        }, SetOptions(merge: true));

      } catch (dbError) {
        print("🚨 DB 저장 실패: $dbError");
      }

      if (context.mounted) Navigator.pop(context); 

    } catch (e) {
      if (context.mounted) {
        Navigator.pop(context);
        _showCustomDialog(context, "에러", "요정이 멈춘 이유:\n$e");
      }
    }
  }

  Future<void> _showChatSummary(BuildContext context) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const AlertDialog(
        content: Row(
          children: [
            CircularProgressIndicator(color: Colors.purple),
            SizedBox(width: 20),
            Expanded(child: Text("AI가 대화 내용을 요약 중입니다... 🪄", style: TextStyle(fontWeight: FontWeight.bold))),
          ],
        ),
      ),
    );

    try {
      final querySnapshot = await FirebaseFirestore.instance
          .collection('chatRooms') 
          .doc(widget.roomId) 
          .collection('messages')
          .orderBy('createdAt', descending: true) 
          .limit(30)
          .get();

      if (querySnapshot.docs.isEmpty) {
        Navigator.pop(context); 
        _showCustomDialog(context, "알림", "아직 나누어진 대화가 없어요! 첫 대화를 시작해 보세요 💬");
        return;
      }

      StringBuffer chatBuffer = StringBuffer();
      for (var doc in querySnapshot.docs.reversed) {
        final data = doc.data();
        final sender = data['senderName'] ?? '익명';
        final message = data['text'] ?? '';
        chatBuffer.writeln('$sender: $message');
      }

      final model = GenerativeModel(
        model: 'gemini-3.6-flash',
        apiKey: dotenv.env['GEMINI_API_KEY'] ?? '', 
      );

      final prompt = """
      너는 번개 모임 채팅방의 센스 있는 AI 매니저야.
      아래의 최근 채팅 내용을 바탕으로, 늦게 들어온 참여자를 위해 핵심 내용을 3가지로 압축해서 요약해 줘.
      - 말투는 친근하고 유쾌하게 (~요, ~임!)
      - 마크다운이나 특수문자 과도한 사용 금지. 오직 텍스트 위주로 깔끔하게.
      
      [채팅 내용]
      ${chatBuffer.toString()}
      """;

      final response = await model.generateContent([Content.text(prompt)]);
      final summaryText = response.text ?? '요약을 생성하지 못했어요 🥲';

      if (!context.mounted) return;
      Navigator.pop(context); 

      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Row(
            children: [
              Icon(Icons.auto_awesome, color: Colors.purple),
              SizedBox(width: 8),
              Text("AI 늦참 요약 봇", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
            ],
          ),
          content: Text(
            summaryText,
            style: const TextStyle(fontSize: 15, height: 1.5, color: Colors.black87),
          ),
          actions: [
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.purple, foregroundColor: Colors.white),
              onPressed: () => Navigator.pop(context),
              child: const Text("확인 완료! 👍"),
            ),
          ],
        ),
      );
    } catch (e) {
      if (!context.mounted) return;
      Navigator.pop(context); 
      _showCustomDialog(context, "에러", "요약을 불러오는 데 실패했습니다: $e");
    }
  }

  void _showCustomDialog(BuildContext context, String title, String content) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
        content: Text(content),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("확인")),
        ],
      ),
    );
  }

  Widget _buildBadge(String text, MaterialColor color) {
    if (text == '비공개') return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color[50],
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color[200]!),
      ),
      child: Text(
        text,
        style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: color[700]),
      ),
    );
  }

  // 💡 [핵심 추가] 팝업에서 유저를 실제로 신고 및 차단하는 로직
  Future<void> _reportAndBlockUser(String targetUid, String targetName) async {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) return;

    final reasonController = TextEditingController();

    final bool? confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.report_problem, color: Colors.red),
            SizedBox(width: 8),
            Text('신고 및 차단'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('[$targetName]님을 차단하시겠습니까?\n차단된 유저의 채팅은 더 이상 보이지 않습니다.'),
            const SizedBox(height: 16),
            TextField(
              controller: reasonController,
              decoration: InputDecoration(
                hintText: '신고 사유를 적어주세요 (선택)',
                filled: true,
                fillColor: Colors.grey[100],
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
              ),
              maxLines: 2,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('취소', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('차단하기', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      // 1. reports 컬렉션에 악성 유저 신고 기록 접수
      await FirebaseFirestore.instance.collection('reports').add({
        'reporterId': currentUser.uid,
        'reportedId': targetUid,
        'reason': reasonController.text,
        'timestamp': FieldValue.serverTimestamp(),
      });

      // 2. 내 정보(users)에 차단 유저 UID 추가
      await FirebaseFirestore.instance.collection('users').doc(currentUser.uid).update({
        'blockedUsers': FieldValue.arrayUnion([targetUid]),
      });

      // 3. 로컬 상태 업데이트 (지금 띄워진 채팅창에서 즉시 글을 숨기기 위해)
      setState(() {
        _blockedUsers.add(targetUid);
      });

      if (mounted) {
        Navigator.pop(context); // 프로필 팝업 닫기
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('[$targetName]님을 차단했습니다. 더 이상 메시지가 보이지 않습니다.')),
        );
      }
    } catch (e) {
      print("차단 오류: $e");
    }
  }

  void _showUserProfileDialog(String targetUid) {
    if (targetUid == 'ai_fairy') return; 

    showDialog(
      context: context,
      builder: (context) {
        return Dialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          child: FutureBuilder<DocumentSnapshot>(
            future: FirebaseFirestore.instance.collection('users').doc(targetUid).get(),
            builder: (context, snapshot) {
              if (!snapshot.hasData) {
                return const SizedBox(height: 200, child: Center(child: CircularProgressIndicator()));
              }

              final userData = snapshot.data!.data() as Map<String, dynamic>?;
              if (userData == null) {
                return const SizedBox(height: 200, child: Center(child: Text('유저 정보를 찾을 수 없습니다.')));
              }

              final nickname = userData['displayName'] ?? '이름 없음';
              final photoUrl = userData['photoUrl'];
              final ageGroup = userData['ageGroup'] ?? '비공개';
              final gender = userData['gender'] ?? '비공개';
              final mbti = userData['mbti'] ?? '비공개';
              final mannerVolt = userData['mannerVolt'] ?? 0;

              return Container(
                padding: const EdgeInsets.all(24.0),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(24),
                ),
                child: Stack(
                  children: [
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        CircleAvatar(
                          radius: 45,
                          backgroundColor: Colors.green[50],
                          backgroundImage: photoUrl != null ? NetworkImage(photoUrl) : null,
                          child: photoUrl == null ? const Icon(Icons.person, color: Colors.green, size: 45) : null,
                        ),
                        const SizedBox(height: 16),
                        Text(nickname, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 20),
                        Wrap(
                          alignment: WrapAlignment.center,
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            _buildBadge(ageGroup, Colors.blue),
                            _buildBadge(gender, Colors.pink),
                            _buildBadge(mbti, Colors.purple),
                            _buildBadge('⚡ $mannerVolt V', Colors.orange),
                          ],
                        ),
                        const SizedBox(height: 24),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            onPressed: () => Navigator.pop(context),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.green,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              elevation: 0,
                            ),
                            child: const Text('닫기', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                          ),
                        ),
                      ],
                    ),
                    // 💡 [UI 추가] 우측 상단 🚨 차단/신고 아이콘 버튼
                    Positioned(
                      top: -10,
                      right: -10,
                      child: IconButton(
                        icon: const Icon(Icons.block, color: Colors.redAccent),
                        tooltip: '차단 및 신고',
                        onPressed: () => _reportAndBlockUser(targetUid, nickname),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        );
      },
    );
  }

  Widget _buildAvatar(String senderId, String senderName, bool isAiFairy) {
    return GestureDetector(
      onTap: () => _showUserProfileDialog(senderId), 
      child: Column(
        children: [
          CircleAvatar(
            radius: 18,
            backgroundColor: isAiFairy ? Colors.orange[100] : Colors.green[100],
            child: Icon(
              isAiFairy ? Icons.auto_awesome : Icons.person, 
              size: 20, 
              color: isAiFairy ? Colors.orange : Colors.green[700]
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;

    return Scaffold(
      backgroundColor: Colors.grey[50], 
      appBar: AppBar(
        title: Text(widget.roomTitle, style: const TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.green,
        foregroundColor: Colors.white,
        elevation: 1,
        actions: [
          IconButton(
            icon: const Icon(Icons.lightbulb_outline, color: Colors.yellowAccent),
            tooltip: 'AI 아이스브레이킹',
            onPressed: () => _triggerIcebreaker(context),
          ),
          IconButton(
            icon: const Icon(Icons.auto_awesome),
            tooltip: 'AI 채팅 요약',
            onPressed: () => _showChatSummary(context),
          ),
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
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                  itemCount: messages.length,
                  itemBuilder: (context, index) {
                    final data = messages[index].data();
                    final isMe = data['senderId'] == uid;
                    final senderId = data['senderId'] ?? '';
                    final text = data['text'] ?? '';
                    final senderName = data['senderName'] ?? '익명';
                    final type = data['type'] ?? 'text';
                    final isAiFairy = senderId == 'ai_fairy';

                    // 💡 [핵심 로직] 내가 차단한 유저의 메시지라면 UI에서 렌더링하지 않음 (숨김 처리)
                    if (_blockedUsers.contains(senderId)) {
                      return const SizedBox.shrink(); 
                    }

                    return Container(
                      margin: const EdgeInsets.only(bottom: 20),
                      child: Row(
                        mainAxisAlignment: isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (!isMe) _buildAvatar(senderId, senderName, isAiFairy),
                          if (!isMe) const SizedBox(width: 8),

                          Flexible(
                            child: Column(
                              crossAxisAlignment: isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                              children: [
                                if (!isMe)
                                  Padding(
                                    padding: const EdgeInsets.only(bottom: 4, left: 4),
                                    child: Text(
                                      senderName, 
                                      style: TextStyle(
                                        fontSize: 13, 
                                        fontWeight: FontWeight.bold, 
                                        color: isAiFairy ? Colors.orange[800] : Colors.black54
                                      )
                                    ),
                                  ),
                                
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                  decoration: BoxDecoration(
                                    color: isMe ? Colors.green : (isAiFairy ? Colors.orange[50] : Colors.white),
                                    borderRadius: BorderRadius.only(
                                      topLeft: const Radius.circular(20),
                                      topRight: const Radius.circular(20),
                                      bottomLeft: Radius.circular(isMe ? 20 : 4), 
                                      bottomRight: Radius.circular(isMe ? 4 : 20),
                                    ),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black.withOpacity(0.05),
                                        blurRadius: 5,
                                        offset: const Offset(0, 2),
                                      )
                                    ],
                                    border: isAiFairy ? Border.all(color: Colors.orange[300]!, width: 1) : null,
                                  ),
                                  child: Text(
                                    text,
                                    style: TextStyle(
                                      color: isMe ? Colors.white : Colors.black87,
                                      fontSize: type == 'emoji' ? 28 : 15,
                                      height: 1.4,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),

                          if (isMe) const SizedBox(width: 8),
                          if (isMe) _buildAvatar(senderId, senderName, false),
                        ],
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
                child: Container(
                  padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, -2))],
                  ),
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
                            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
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