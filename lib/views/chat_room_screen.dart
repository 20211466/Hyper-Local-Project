import 'dart:async';

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
  bool _isSendingMessage = false;
  bool _isAiBusy = false;
  BuildContext? _aiLoadingDialogContext;
  String _participantCacheKey = '';
  Future<List<_ChatParticipant>>? _participantFuture;

  // 💡 [추가] 차단한 유저들의 UID를 담아둘 리스트
  List<String> _blockedUsers = [];

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
    _markAsReadSafely();
    _loadBlockedUsers(); // 채팅방 진입 시 차단 목록 불러오기
  }

  Future<void> _markAsReadSafely() async {
    try {
      await _chatService.markAsRead(widget.roomId);
    } catch (error) {
      debugPrint('[읽음 처리 실패] $error');
    }
  }

  // 💡 [추가] 내 차단 목록을 DB에서 가져오는 함수
  Future<void> _loadBlockedUsers() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .get();
      final data = doc.data();
      if (data != null && data['blockedUsers'] != null) {
        if (mounted) {
          setState(() {
            _blockedUsers = List<String>.from(data['blockedUsers']);
          });
        }
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
    if (text.trim().isEmpty || _isSendingMessage) return;

    setState(() => _isSendingMessage = true);
    try {
      await _chatService.sendMessage(
        roomId: widget.roomId,
        text: text,
        type: type,
      );
      if (!mounted) return;
      _messageController.clear();
      await _markAsReadSafely();
    } catch (error) {
      debugPrint('[메시지 전송 실패] $error');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('메시지를 보내지 못했습니다. 채팅방 참가 상태를 확인해 주세요.\n$error'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 5),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSendingMessage = false);
    }
  }

  Future<void> _leaveChatAndMeeting() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    try {
      await _chatService.leaveRoom(widget.roomId);
      await FirebaseFirestore.instance
          .collection('meetings')
          .doc(widget.roomId)
          .update({
            'participants': FieldValue.arrayRemove([uid]),
            'currentParticipants': FieldValue.increment(-1),
          });

      if (mounted) {
        Navigator.pop(context);
        Navigator.pop(context);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('모임 참여가 취소되었습니다.')));
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
            child: const Text(
              '예',
              style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }

  void _showAiLoading(String message, {Color color = Colors.green}) {
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        _aiLoadingDialogContext = dialogContext;
        return AlertDialog(
          content: Row(
            children: [
              CircularProgressIndicator(color: color),
              const SizedBox(width: 16),
              Expanded(
                child: Text(
                  message,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  void _closeAiLoading() {
    final dialogContext = _aiLoadingDialogContext;
    _aiLoadingDialogContext = null;
    if (dialogContext != null && dialogContext.mounted) {
      Navigator.of(dialogContext).pop();
    }
  }

  String _friendlyAiError(Object error, String featureName) {
    if (error is TimeoutException) {
      return '$featureName 응답이 12초 안에 도착하지 않아 중단했습니다. 네트워크나 Gemini API 사용량을 확인한 뒤 다시 시도해 주세요.';
    }
    final raw = error.toString();
    if (raw.contains('429') || raw.toLowerCase().contains('quota')) {
      return 'Gemini API 사용량 한도에 도달했습니다. 잠시 후 다시 시도해 주세요.';
    }
    if (raw.contains('403') || raw.contains('401')) {
      return 'Gemini API 인증에 실패했습니다. .env의 API 키와 사용 권한을 확인해 주세요.';
    }
    if (raw.contains('404') || raw.toLowerCase().contains('not found')) {
      return '요청한 Gemini 모델을 찾을 수 없습니다. 모델 설정을 확인해 주세요.';
    }
    return '$featureName 기능을 실행하지 못했습니다.\n원인: $raw';
  }

  Future<void> _triggerIcebreaker(BuildContext context) async {
    if (_isAiBusy) return;
    final apiKey = dotenv.env['GEMINI_API_KEY']?.trim() ?? '';
    if (apiKey.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Gemini API 키를 찾을 수 없습니다. .env 파일을 확인해 주세요.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() => _isAiBusy = true);
    bool loadingVisible = false;
    try {
      _showAiLoading('AI 요정이 첫 대화 질문을 만들고 있어요...', color: Colors.orange);
      loadingVisible = true;

      final meetingSnapshot = await FirebaseFirestore.instance
          .collection('meetings')
          .doc(widget.roomId)
          .get()
          .timeout(const Duration(seconds: 6));
      final meetingData = meetingSnapshot.data();
      if (meetingData == null) {
        throw StateError('모임 정보를 찾을 수 없습니다.');
      }

      final category = (meetingData['category'] ?? '모임').toString();
      final title = (meetingData['title'] ?? widget.roomTitle).toString();
      final participantValues = meetingData['participants'];
      final participantIds = participantValues is List
          ? participantValues
                .map((value) => value.toString())
                .where((value) => value.isNotEmpty)
                .take(5)
                .toList()
          : <String>[];

      // 참여자 프로필을 한 명씩 기다리지 않고 병렬로 읽어 대기 시간을 줄입니다.
      final profileSnapshots = await Future.wait(
        participantIds.map(
          (uid) => FirebaseFirestore.instance
              .collection('users')
              .doc(uid)
              .get()
              .timeout(const Duration(seconds: 5)),
        ),
      );
      final mbtiList = profileSnapshots
          .map((snapshot) => (snapshot.data()?['mbti'] ?? '').toString())
          .where((mbti) => mbti.isNotEmpty && mbti != '비공개')
          .toList();

      final model = GenerativeModel(
        model: 'gemini-3.5-flash-lite',
        apiKey: apiKey,
        generationConfig: GenerationConfig(
          maxOutputTokens: 110,
          temperature: 0.65,
        ),
      );
      final prompt =
          '''
동네 번개 모임 채팅방의 친근한 AI 요정이야.
모임: $category / $title
참여자 MBTI: ${mbtiList.isEmpty ? '정보 없음' : mbtiList.join(', ')}
대화 시작용 질문 1개를 한국어 반말로 짧고 자연스럽게 만들어.
첫 문장은 "안녕하세요! AI 요정입니다."로 시작하고 전체 2문장 이내로 작성해.
''';

      final response = await model
          .generateContent([Content.text(prompt)])
          .timeout(const Duration(seconds: 12));
      final icebreakerText = response.text?.trim() ?? '';
      if (icebreakerText.isEmpty) {
        throw const FormatException('AI가 질문을 생성하지 못했습니다. 다시 시도해 주세요.');
      }

      final roomRef = FirebaseFirestore.instance
          .collection('chatRooms')
          .doc(widget.roomId);
      final messageRef = roomRef.collection('messages').doc();
      final batch = FirebaseFirestore.instance.batch();
      batch.set(messageRef, {
        'text': icebreakerText,
        'senderId': 'ai_fairy',
        'senderName': 'AI 요정',
        'createdAt': FieldValue.serverTimestamp(),
        'type': 'text',
      });
      batch.update(roomRef, {
        'lastMessage': icebreakerText,
        'lastMessageAt': FieldValue.serverTimestamp(),
        'lastSenderId': 'ai_fairy',
      });
      // 메시지와 채팅방 마지막 메시지 정보를 한 번에 저장해 네트워크 왕복을 줄입니다.
      await batch.commit().timeout(const Duration(seconds: 6));

      if (loadingVisible && mounted) {
        _closeAiLoading();
        loadingVisible = false;
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('AI 요정의 질문을 채팅방에 등록했습니다.'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (error, stackTrace) {
      debugPrint('[AI 아이스브레이킹 실패] $error');
      debugPrintStack(stackTrace: stackTrace);
      if (loadingVisible && mounted) {
        _closeAiLoading();
        loadingVisible = false;
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_friendlyAiError(error, 'AI 아이스브레이킹')),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 6),
          ),
        );
      }
    } finally {
      if (loadingVisible && mounted) _closeAiLoading();
      if (mounted) setState(() => _isAiBusy = false);
    }
  }

  Future<void> _showChatSummary(BuildContext context) async {
    if (_isAiBusy) return;
    final apiKey = dotenv.env['GEMINI_API_KEY']?.trim() ?? '';
    if (apiKey.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Gemini API 키를 찾을 수 없습니다. .env 파일을 확인해 주세요.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() => _isAiBusy = true);
    bool loadingVisible = false;
    try {
      _showAiLoading('최근 대화에서 핵심 내용만 정리하고 있어요...', color: Colors.purple);
      loadingVisible = true;

      // 요약 입력을 최근 20개로 줄이고 메시지별 길이를 제한해 응답 시간을 단축합니다.
      final querySnapshot = await FirebaseFirestore.instance
          .collection('chatRooms')
          .doc(widget.roomId)
          .collection('messages')
          .orderBy('createdAt', descending: true)
          .limit(20)
          .get()
          .timeout(const Duration(seconds: 6));

      if (querySnapshot.docs.isEmpty) {
        if (loadingVisible && mounted) {
          _closeAiLoading();
          loadingVisible = false;
        }
        if (mounted) {
          _showCustomDialog(context, '알림', '아직 나누어진 대화가 없어요. 첫 대화를 시작해 보세요!');
        }
        return;
      }

      final chatLines = <String>[];
      for (final doc in querySnapshot.docs.reversed) {
        final data = doc.data();
        final sender = (data['senderName'] ?? '익명').toString();
        var message = (data['text'] ?? '')
            .toString()
            .replaceAll(RegExp(r'\s+'), ' ')
            .trim();
        if (message.length > 160) message = '${message.substring(0, 160)}…';
        if (message.isNotEmpty) chatLines.add('$sender: $message');
      }

      final model = GenerativeModel(
        model: 'gemini-3.5-flash-lite',
        apiKey: apiKey,
        generationConfig: GenerationConfig(
          maxOutputTokens: 220,
          temperature: 0.2,
        ),
      );
      final prompt =
          '''
아래 동네 모임 채팅을 늦게 참여한 사람을 위해 요약해.
중요한 내용 3가지만 한국어로 간결하게 정리해. 시간, 장소, 준비물, 약속이 있으면 우선 포함해.
불필요한 인사와 반복은 제외하고, 대화에 없는 정보는 추측하지 마.
[최근 채팅]
${chatLines.join('\n')}
''';
      final response = await model
          .generateContent([Content.text(prompt)])
          .timeout(const Duration(seconds: 12));
      final summaryText = response.text?.trim() ?? '';
      if (summaryText.isEmpty) {
        throw const FormatException('AI가 요약을 생성하지 못했습니다. 다시 시도해 주세요.');
      }

      if (loadingVisible && mounted) {
        _closeAiLoading();
        loadingVisible = false;
      }
      if (!mounted) return;
      showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: const Row(
            children: [
              Icon(Icons.auto_awesome, color: Colors.purple),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'AI 늦참 요약 봇',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                ),
              ),
            ],
          ),
          content: SingleChildScrollView(
            child: Text(
              summaryText,
              style: const TextStyle(
                fontSize: 15,
                height: 1.5,
                color: Colors.black87,
              ),
            ),
          ),
          actions: [
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.purple,
                foregroundColor: Colors.white,
              ),
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('확인'),
            ),
          ],
        ),
      );
    } catch (error, stackTrace) {
      debugPrint('[AI 채팅 요약 실패] $error');
      debugPrintStack(stackTrace: stackTrace);
      if (loadingVisible && mounted) {
        _closeAiLoading();
        loadingVisible = false;
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_friendlyAiError(error, 'AI 채팅 요약')),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 6),
          ),
        );
      }
    } finally {
      if (loadingVisible && mounted) _closeAiLoading();
      if (mounted) setState(() => _isAiBusy = false);
    }
  }

  void _showCustomDialog(BuildContext context, String title, String content) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
        content: Text(content),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("확인"),
          ),
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
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.bold,
          color: color[700],
        ),
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
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
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
            child: const Text(
              '차단하기',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
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
      await FirebaseFirestore.instance
          .collection('users')
          .doc(currentUser.uid)
          .update({
            'blockedUsers': FieldValue.arrayUnion([targetUid]),
          });

      // 3. 로컬 상태 업데이트 (지금 띄워진 채팅창에서 즉시 글을 숨기기 위해)
      setState(() {
        _blockedUsers.add(targetUid);
      });

      if (mounted) {
        Navigator.pop(context); // 프로필 팝업 닫기
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('[$targetName]님을 차단했습니다. 더 이상 메시지가 보이지 않습니다.'),
          ),
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
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
          child: FutureBuilder<DocumentSnapshot>(
            future: FirebaseFirestore.instance
                .collection('users')
                .doc(targetUid)
                .get(),
            builder: (context, snapshot) {
              if (!snapshot.hasData) {
                return const SizedBox(
                  height: 200,
                  child: Center(child: CircularProgressIndicator()),
                );
              }

              final userData = snapshot.data!.data() as Map<String, dynamic>?;
              if (userData == null) {
                return const SizedBox(
                  height: 200,
                  child: Center(child: Text('유저 정보를 찾을 수 없습니다.')),
                );
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
                          backgroundImage: photoUrl != null
                              ? NetworkImage(photoUrl)
                              : null,
                          child: photoUrl == null
                              ? const Icon(
                                  Icons.person,
                                  color: Colors.green,
                                  size: 45,
                                )
                              : null,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          nickname,
                          style: const TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
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
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              elevation: 0,
                            ),
                            child: const Text(
                              '닫기',
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
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
                        onPressed: () =>
                            _reportAndBlockUser(targetUid, nickname),
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
              color: isAiFairy ? Colors.orange : Colors.green[700],
            ),
          ),
        ],
      ),
    );
  }

  Future<List<_ChatParticipant>> _fetchChatParticipants(
    List<String> participantIds,
    String creatorId,
  ) async {
    final snapshots = await Future.wait(
      participantIds.map(
        (uid) => FirebaseFirestore.instance.collection('users').doc(uid).get(),
      ),
    );
    return List<_ChatParticipant>.generate(participantIds.length, (index) {
      final uid = participantIds[index];
      final data = snapshots[index].data() ?? <String, dynamic>{};
      return _ChatParticipant(uid: uid, data: data, isHost: uid == creatorId);
    });
  }

  Widget _buildParticipantsTab() {
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('meetings')
          .doc(widget.roomId)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(
            child: Text(
              '참여자 정보를 불러오지 못했습니다.\n${snapshot.error}',
              textAlign: TextAlign.center,
            ),
          );
        }
        if (!snapshot.hasData) {
          return const Center(
            child: CircularProgressIndicator(color: Colors.green),
          );
        }
        final meetingData = snapshot.data!.data();
        if (meetingData == null) {
          return const Center(child: Text('모임 정보를 찾을 수 없습니다.'));
        }

        final creatorId = (meetingData['creatorId'] ?? '').toString();
        final rawParticipants = meetingData['participants'];
        final participantIds = rawParticipants is List
            ? rawParticipants
                  .map((value) => value.toString())
                  .where((uid) => uid.isNotEmpty)
                  .toSet()
                  .toList()
            : <String>[];
        if (creatorId.isNotEmpty && !participantIds.contains(creatorId)) {
          participantIds.insert(0, creatorId);
        }
        final cacheKey = '${creatorId}|${participantIds.join(',')}';
        if (_participantFuture == null || _participantCacheKey != cacheKey) {
          _participantCacheKey = cacheKey;
          _participantFuture = _fetchChatParticipants(
            participantIds,
            creatorId,
          );
        }

        return FutureBuilder<List<_ChatParticipant>>(
          future: _participantFuture,
          builder: (context, membersSnapshot) {
            if (membersSnapshot.hasError) {
              return Center(
                child: Text(
                  '회원 정보를 불러오지 못했습니다.\n${membersSnapshot.error}',
                  textAlign: TextAlign.center,
                ),
              );
            }
            if (!membersSnapshot.hasData) {
              return const Center(
                child: CircularProgressIndicator(color: Colors.green),
              );
            }
            final members = membersSnapshot.data!;
            final currentCount =
                (meetingData['currentParticipants'] as num?)?.toInt() ??
                members.length;
            final maxCount =
                (meetingData['maxParticipants'] as num?)?.toInt() ?? 0;
            return Column(
              children: [
                Container(
                  width: double.infinity,
                  margin: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.green.shade50,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.groups_rounded,
                        color: Colors.green,
                        size: 28,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              '모임 참여자',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              maxCount > 0
                                  ? '$currentCount / $maxCount명 참여 중'
                                  : '$currentCount명 참여 중',
                              style: const TextStyle(
                                color: Colors.black54,
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        tooltip: '참여자 새로고침',
                        onPressed: () => setState(() {
                          _participantCacheKey = '';
                          _participantFuture = null;
                        }),
                        icon: const Icon(Icons.refresh, color: Colors.green),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: members.isEmpty
                      ? const Center(child: Text('아직 참여자가 없습니다.'))
                      : ListView.separated(
                          padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
                          itemCount: members.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(height: 8),
                          itemBuilder: (context, index) {
                            final member = members[index];
                            final data = member.data;
                            final name =
                                (data['displayName'] ??
                                        data['nickname'] ??
                                        '이름 없음')
                                    .toString();
                            final photoUrl = (data['photoUrl'] ?? '')
                                .toString();
                            final mbti = (data['mbti'] ?? '비공개').toString();
                            final ageGroup = (data['ageGroup'] ?? '비공개')
                                .toString();
                            final gender = (data['gender'] ?? '비공개').toString();
                            final mannerVolt = (data['mannerVolt'] ?? 0)
                                .toString();
                            return Card(
                              elevation: 1,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                              child: ListTile(
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 14,
                                  vertical: 6,
                                ),
                                leading: CircleAvatar(
                                  radius: 24,
                                  backgroundColor: Colors.green.shade50,
                                  backgroundImage: photoUrl.isNotEmpty
                                      ? NetworkImage(photoUrl)
                                      : null,
                                  child: photoUrl.isEmpty
                                      ? const Icon(
                                          Icons.person,
                                          color: Colors.green,
                                        )
                                      : null,
                                ),
                                title: Row(
                                  children: [
                                    Flexible(
                                      child: Text(
                                        name,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                    if (member.isHost) ...[
                                      const SizedBox(width: 6),
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 7,
                                          vertical: 3,
                                        ),
                                        decoration: BoxDecoration(
                                          color: Colors.orange.shade50,
                                          borderRadius: BorderRadius.circular(
                                            8,
                                          ),
                                        ),
                                        child: const Text(
                                          '방장',
                                          style: TextStyle(
                                            color: Colors.deepOrange,
                                            fontSize: 11,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                                subtitle: Padding(
                                  padding: const EdgeInsets.only(top: 5),
                                  child: Text(
                                    'MBTI $mbti  ·  $ageGroup  ·  $gender\n매너 볼트 $mannerVolt V',
                                    style: const TextStyle(
                                      height: 1.5,
                                      fontSize: 12,
                                    ),
                                  ),
                                ),
                                isThreeLine: true,
                                trailing: const Icon(
                                  Icons.chevron_right,
                                  color: Colors.grey,
                                ),
                                onTap: () => _showUserProfileDialog(member.uid),
                              ),
                            );
                          },
                        ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildChatTab(String? uid) {
    return Column(
      children: [
        Expanded(
          child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: _chatService.messagesStream(widget.roomId),
            builder: (context, snapshot) {
              if (snapshot.hasError)
                return Center(
                  child: Text('채팅을 불러오지 못했습니다.\n${snapshot.error}'),
                );
              if (!snapshot.hasData)
                return const Center(child: CircularProgressIndicator());
              final messages = snapshot.data!.docs;
              if (messages.isEmpty) {
                return const Center(
                  child: Text(
                    '첫 메시지를 보내보세요!',
                    style: TextStyle(color: Colors.black54),
                  ),
                );
              }
              WidgetsBinding.instance.addPostFrameCallback(
                (_) => _markAsReadSafely(),
              );
              return ListView.builder(
                reverse: true,
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 16,
                ),
                itemCount: messages.length,
                itemBuilder: (context, index) {
                  final data = messages[index].data();
                  final senderId = (data['senderId'] ?? '').toString();
                  final isMe = senderId == uid;
                  final text = (data['text'] ?? '').toString();
                  final senderName = (data['senderName'] ?? '익명').toString();
                  final type = (data['type'] ?? 'text').toString();
                  final isAiFairy = senderId == 'ai_fairy';
                  if (_blockedUsers.contains(senderId))
                    return const SizedBox.shrink();
                  return Container(
                    margin: const EdgeInsets.only(bottom: 20),
                    child: Row(
                      mainAxisAlignment: isMe
                          ? MainAxisAlignment.end
                          : MainAxisAlignment.start,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (!isMe)
                          _buildAvatar(senderId, senderName, isAiFairy),
                        if (!isMe) const SizedBox(width: 8),
                        Flexible(
                          child: Column(
                            crossAxisAlignment: isMe
                                ? CrossAxisAlignment.end
                                : CrossAxisAlignment.start,
                            children: [
                              if (!isMe)
                                Padding(
                                  padding: const EdgeInsets.only(
                                    bottom: 4,
                                    left: 4,
                                  ),
                                  child: Text(
                                    senderName,
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.bold,
                                      color: isAiFairy
                                          ? Colors.orange[800]
                                          : Colors.black54,
                                    ),
                                  ),
                                ),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 12,
                                ),
                                decoration: BoxDecoration(
                                  color: isMe
                                      ? Colors.green
                                      : (isAiFairy
                                            ? Colors.orange[50]
                                            : Colors.white),
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
                                    ),
                                  ],
                                  border: isAiFairy
                                      ? Border.all(
                                          color: Colors.orange[300]!,
                                          width: 1,
                                        )
                                      : null,
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
              children: _emojis
                  .map(
                    (emoji) => InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: () async {
                        _messageController.text = emoji;
                        await _send(type: 'emoji');
                      },
                      child: Center(
                        child: Text(
                          emoji,
                          style: const TextStyle(fontSize: 26),
                        ),
                      ),
                    ),
                  )
                  .toList(),
            ),
          ),
        StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          stream: FirebaseFirestore.instance
              .collection('meetings')
              .doc(widget.roomId)
              .snapshots(),
          builder: (context, snapshot) {
            bool isExpired = false;
            final data = snapshot.data?.data();
            final deadlineValue = data?['deadline'];
            DateTime? deadline;
            if (deadlineValue is Timestamp) deadline = deadlineValue.toDate();
            if (deadlineValue is DateTime) deadline = deadlineValue;
            if (deadline != null && !deadline.isAfter(DateTime.now()))
              isExpired = true;
            if (isExpired) {
              return SafeArea(
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 20),
                  color: Colors.grey[200],
                  child: const Text(
                    '종료된 번개의 채팅방입니다. 더 이상 메시지를 보낼 수 없습니다.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.black54,
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                ),
              );
            }
            return SafeArea(
              child: Container(
                padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
                decoration: BoxDecoration(
                  color: Colors.white,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.05),
                      blurRadius: 10,
                      offset: const Offset(0, -2),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    IconButton(
                      icon: Icon(
                        _showEmojiPanel
                            ? Icons.keyboard
                            : Icons.emoji_emotions_outlined,
                      ),
                      color: Colors.green,
                      onPressed: () =>
                          setState(() => _showEmojiPanel = !_showEmojiPanel),
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
                            horizontal: 16,
                            vertical: 12,
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(24),
                            borderSide: BorderSide.none,
                          ),
                        ),
                        onTap: () {
                          if (_showEmojiPanel)
                            setState(() => _showEmojiPanel = false);
                        },
                      ),
                    ),
                    IconButton(
                      icon: _isSendingMessage
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.send),
                      color: Colors.green,
                      onPressed: _isSendingMessage ? null : _send,
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: Colors.grey[50],
        appBar: AppBar(
          title: Text(
            widget.roomTitle,
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          backgroundColor: Colors.green,
          foregroundColor: Colors.white,
          elevation: 1,
          bottom: const TabBar(
            indicatorColor: Colors.white,
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white70,
            tabs: [
              Tab(icon: Icon(Icons.chat_bubble_outline), text: '채팅'),
              Tab(icon: Icon(Icons.people_alt_outlined), text: '참여자 정보'),
            ],
          ),
          actions: [
            IconButton(
              icon: _isAiBusy
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(
                      Icons.lightbulb_outline,
                      color: Colors.yellowAccent,
                    ),
              tooltip: 'AI 아이스브레이킹',
              onPressed: _isAiBusy ? null : () => _triggerIcebreaker(context),
            ),
            IconButton(
              icon: const Icon(Icons.auto_awesome),
              tooltip: 'AI 채팅 요약',
              onPressed: _isAiBusy ? null : () => _showChatSummary(context),
            ),
            IconButton(
              icon: const Icon(Icons.exit_to_app),
              tooltip: '나가기',
              onPressed: _showExitDialog,
            ),
          ],
        ),
        body: TabBarView(
          children: [_buildChatTab(uid), _buildParticipantsTab()],
        ),
      ),
    );
  }
}

class _ChatParticipant {
  final String uid;
  final Map<String, dynamic> data;
  final bool isHost;

  const _ChatParticipant({
    required this.uid,
    required this.data,
    required this.isHost,
  });
}
