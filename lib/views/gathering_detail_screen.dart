import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_generative_ai/google_generative_ai.dart'; 
import 'dart:convert'; 
import '../models/gathering_model.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

class GatheringDetailScreen extends StatelessWidget {
  final Gathering gathering;

  const GatheringDetailScreen({super.key, required this.gathering});

  @override
  Widget build(BuildContext context) {
    // 💡 현재 로그인한 유저 정보 가져오기
    final currentUserUid = FirebaseAuth.instance.currentUser?.uid;

    return Scaffold(
      appBar: AppBar(
        title: const Text("모임 상세 정보", style: TextStyle(fontWeight: FontWeight.bold)), 
        backgroundColor: Colors.green,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 1. 모임 기본 정보
            Text(
              gathering.title,
              style: const TextStyle(fontSize: 26, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                const Icon(Icons.access_time, size: 20, color: Colors.orange),
                const SizedBox(width: 8),
                Text(
                  "모임 시간: ${gathering.date}",
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
                ),
              ],
            ),
            const SizedBox(height: 20),
            const Divider(thickness: 1.5),
            const SizedBox(height: 10),

            // 2. 모임 상세 설명
            const Text(
              "모임 설명",
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.grey[100],
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                gathering.description,
                style: const TextStyle(fontSize: 16, height: 1.5),
              ),
            ),
            
            // 💡 [2단계 적용] 모임 설명 바로 아래에 AI 스마트 매칭 카드 쏙 끼워넣기!
            AiMatchingCard(
              meetingTitle: gathering.title, 
              meetingDescription: gathering.description,
            ),
            
            const SizedBox(height: 24),

            // 3. 참여자 목록 및 뱃지 영역
            const Text(
              "참여자 프로필",
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            
            Expanded(
              child: StreamBuilder<QuerySnapshot>(
                stream: FirebaseFirestore.instance
                    .collection('meetings')
                    .where('title', isEqualTo: gathering.title)
                    .snapshots(),
                builder: (context, snapshot) {
                  if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                    return const Center(child: CircularProgressIndicator());
                  }

                  final doc = snapshot.data!.docs.first;
                  final data = doc.data() as Map<String, dynamic>;
                  final List participants = data['participants'] ?? [];

                  // 내 참여 여부 확인 ('익명 참여자' 대신 실제 UID 사용)
                  final bool isJoined = currentUserUid != null && participants.contains(currentUserUid);

                  return Column(
                    children: [
                      // 참여자 목록 리스트 렌더링
                      Expanded(
                        child: participants.isEmpty
                            ? const Center(child: Text('아직 참여자가 없습니다.', style: TextStyle(color: Colors.grey)))
                            : ListView.separated(
                                itemCount: participants.length,
                                separatorBuilder: (_, __) => const Divider(),
                                itemBuilder: (context, index) {
                                  final uid = participants[index];
                                  
                                  // 유저 UID를 기반으로 users 컬렉션에서 프로필 정보를 가져옴
                                  return FutureBuilder<DocumentSnapshot>(
                                    future: FirebaseFirestore.instance.collection('users').doc(uid).get(),
                                    builder: (context, userSnapshot) {
                                      if (!userSnapshot.hasData) {
                                        return const ListTile(title: Text('유저 정보 불러오는 중...'));
                                      }
                                      
                                      final userData = userSnapshot.data!.data() as Map<String, dynamic>?;
                                      if (userData == null) return const ListTile(title: Text('알 수 없는 유저'));

                                      final nickname = userData['displayName'] ?? '이름 없음';
                                      final ageGroup = userData['ageGroup'] ?? '비공개';
                                      final gender = userData['gender'] ?? '비공개';
                                      final mbti = userData['mbti'] ?? '비공개';
                                      final mannerVolt = userData['mannerVolt'] ?? 0;
                                      
                                      // 💡 [핵심 방어 로직] 모임 참석 횟수가 3회 이하면 뉴비로 간주! (필드가 없으면 기본값 0)
                                      final meetingCount = userData['meetingCount'] ?? 0;

                                      return ListTile(
                                        contentPadding: EdgeInsets.zero,
                                        leading: CircleAvatar(
                                          backgroundColor: Colors.green[50],
                                          child: const Icon(Icons.person, color: Colors.green),
                                        ),
                                        // 💡 이름 옆에 조건부로 뉴비 뱃지 달아주기
                                        title: Row(
                                          children: [
                                            Text(nickname, style: const TextStyle(fontWeight: FontWeight.bold)),
                                            if (meetingCount <= 3) ...[
                                              const SizedBox(width: 6),
                                              Container(
                                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                                decoration: BoxDecoration(
                                                  color: Colors.green[100],
                                                  borderRadius: BorderRadius.circular(4),
                                                ),
                                                child: Text('🌱 동네 뉴비', style: TextStyle(fontSize: 10, color: Colors.green[800], fontWeight: FontWeight.bold)),
                                              ),
                                            ],
                                          ],
                                        ),
                                        // 💡 프로필 뱃지 출력 (나이대, 성별, MBTI, 매너볼트)
                                        subtitle: Wrap(
                                          spacing: 6,
                                          runSpacing: 4,
                                          children: [
                                            _buildBadge(ageGroup, Colors.blue),
                                            _buildBadge(gender, Colors.pink),
                                            _buildBadge(mbti, Colors.purple),
                                            _buildBadge('⚡ $mannerVolt V', Colors.orange),
                                          ],
                                        ),
                                      );
                                    },
                                  );
                                },
                              ),
                      ),
                      
                      const SizedBox(height: 16),

                      // 참여 인원수 요약
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.people_alt, color: Colors.green),
                          const SizedBox(width: 8),
                          Text(
                            "현재 ${participants.length}명이 모였습니다!",
                            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.green),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),

                      // 4. 참여/취소 버튼 (실제 UID 사용)
                      ElevatedButton(
                        onPressed: currentUserUid == null ? null : () async {
                          try {
                            if (isJoined) {
                              // 참여 취소 로직
                              await doc.reference.update({
                                'participants': FieldValue.arrayRemove([currentUserUid]),
                                'currentParticipants': FieldValue.increment(-1),
                              });
                              if (context.mounted) _showSnackBar(context, "참여를 취소했습니다.", Colors.grey);
                            } else {
                              // 참여 로직
                              await doc.reference.update({
                                'participants': FieldValue.arrayUnion([currentUserUid]),
                                'currentParticipants': FieldValue.increment(1),
                              });
                              
                              // 💡 [핵심 연동] 참여할 때 해당 유저의 meetingCount(참여 횟수)도 1 증가시켜줍니다!
                              await FirebaseFirestore.instance.collection('users').doc(currentUserUid).set({
                                'meetingCount': FieldValue.increment(1)
                              }, SetOptions(merge: true));

                              if (context.mounted) _showSnackBar(context, "🎉 참여가 완료되었습니다!", Colors.green);
                            }
                          } catch (e) {
                            if (context.mounted) _showSnackBar(context, "오류 발생: $e", Colors.red);
                          }
                        },
                        style: ElevatedButton.styleFrom(
                          minimumSize: const Size(double.infinity, 55),
                          backgroundColor: isJoined ? Colors.grey[400] : Colors.green,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                          elevation: isJoined ? 0 : 4,
                        ),
                        child: Text(
                          isJoined ? "참여 취소하기" : "⚡ 이 번개 참여하기",
                          style: const TextStyle(fontSize: 18, color: Colors.white, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  // 💡 프로필 뱃지를 예쁘게 만들어주는 내부 위젯 함수
  Widget _buildBadge(String text, MaterialColor color) {
    if (text == '비공개') return const SizedBox.shrink(); // 비공개면 뱃지 숨김
    return Container(
      margin: const EdgeInsets.only(top: 4),
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

  // 스낵바 표시 함수
  void _showSnackBar(BuildContext context, String message, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message, style: const TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: color,
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }
}

// 💡 AI 매칭 점수를 분석하고 예쁘게 보여주는 커스텀 위젯
class AiMatchingCard extends StatefulWidget {
  final String meetingTitle;
  final String meetingDescription;

  const AiMatchingCard({super.key, required this.meetingTitle, required this.meetingDescription});

  @override
  State<AiMatchingCard> createState() => _AiMatchingCardState();
}

class _AiMatchingCardState extends State<AiMatchingCard> {
  bool _isLoading = true;
  int _score = 0;
  String _reason = '';
  String _errorMessage = '';

  @override
  void initState() {
    super.initState();
    _analyzeMatch();
  }

  Future<void> _analyzeMatch() async {
    try {
      // 1. 내 MBTI 가져오기 (테스트를 위해 기본값 세팅)
      final user = FirebaseAuth.instance.currentUser;
      String myMbti = 'ENFP'; 
      if (user != null) {
        final doc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
        myMbti = (doc.data() as Map<String, dynamic>?)?['mbti'] ?? 'ENFP';
      }

      // 2. 제미나이 3.6 모델 세팅
      final model = GenerativeModel(
        model: 'gemini-3.6-flash',
        apiKey: dotenv.env['GEMINI_API_KEY'] ?? '',
      );

      // 3. AI에게 매칭 점수와 이유를 JSON으로 요구
      final prompt = """
      너는 커뮤니티 앱의 천재 매칭 매니저야.
      내 MBTI는 [$myMbti]야. 
      참여하려는 모임 제목: [${widget.meetingTitle}]
      모임 설명: [${widget.meetingDescription}]
      
      이 모임이 내 성향과 얼마나 잘 맞을지 1~100 사이의 점수와, 왜 그렇게 생각하는지 2줄 이내로 아주 유쾌하게 적어줘.
      마크다운이나 기호 절대 금지. 오직 아래 JSON 형식만 반환해.
      {"score": 95, "reason": "ENFP 특유의 인싸력이라면 이 모임의 분위기 메이커는 따놓은 당상!"}
      """;

      final response = await model.generateContent([Content.text(prompt)]);
      String cleanJson = response.text?.trim() ?? '';
      
      // JSON 찌꺼기 제거
      if (cleanJson.startsWith('```json')) cleanJson = cleanJson.replaceFirst('```json', '');
      if (cleanJson.startsWith('```')) cleanJson = cleanJson.replaceFirst('```', '');
      if (cleanJson.endsWith('```')) cleanJson = cleanJson.substring(0, cleanJson.length - 3);
      
      final data = jsonDecode(cleanJson.trim());
      
      if (mounted) {
        setState(() {
          _score = data['score'] ?? 50;
          _reason = data['reason'] ?? '무난하게 잘 어울릴 모임입니다!';
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = 'AI 분석에 실패했어요 😢';
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.purple[50]!, Colors.blue[50]!],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.purple.withOpacity(0.2)),
        boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 8, offset: Offset(0, 3))],
      ),
      child: _isLoading
          ? const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.purple)),
                SizedBox(width: 12),
                Text("AI가 회원님과의 궁합을 분석 중입니다... 🪄", style: TextStyle(color: Colors.purple, fontWeight: FontWeight.bold)),
              ],
            )
          : _errorMessage.isNotEmpty
              ? Text(_errorMessage, style: const TextStyle(color: Colors.red))
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.auto_awesome, color: Colors.purple),
                        const SizedBox(width: 8),
                        const Text("AI 스마트 매칭", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.black87)),
                        const Spacer(),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: _score >= 80 ? Colors.green : (_score >= 50 ? Colors.orange : Colors.red),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            "$_score점", 
                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(_reason, style: const TextStyle(fontSize: 14, color: Colors.black87, height: 1.5)),
                  ],
                ),
    );
  }
}