import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:url_launcher/url_launcher.dart'; // 💡 외부 지도 앱 실행을 위해 추가
import 'dart:convert'; 
import '../models/gathering_model.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

class GatheringDetailScreen extends StatelessWidget {
  final Gathering gathering;
  final Map<String, dynamic>? meetupData; 

  const GatheringDetailScreen({
    super.key, 
    required this.gathering,
    this.meetupData, 
  });

  // 🚨 [핵심] 외부 지도(카카오맵/네이버지도/구글맵)로 도보 네비게이션 즉시 실행하는 함수
  Future<void> _launchEmergencyNavigation(BuildContext context, double destLat, double destLng, String destName) async {
    // 1. 카카오맵 도보 길찾기 URL Scheme (ep: 도착지 좌표, by: 도보(WALK))
    final Uri kakaoMapUrl = Uri.parse('kakaomap://route?ep=$destLat,$destLng&by=WALK');
    // 2. 네이버지도 도보 길찾기 URL Scheme
    final Uri naverMapUrl = Uri.parse('nmap://route/walk?dlat=$destLat&dlng=$destLng&dname=$destName');
    // 3. 구글맵 도보 길찾기 (웹/앱 범용)
    final Uri googleMapUrl = Uri.parse('https://www.google.com/maps/dir/?api=1&destination=$destLat,$destLng&travelmode=walking');

    try {
      // 카카오맵 먼저 시도
      if (await canLaunchUrl(kakaoMapUrl)) {
        await launchUrl(kakaoMapUrl, mode: LaunchMode.externalApplication);
      } 
      // 실패 시 네이버지도 시도
      else if (await canLaunchUrl(naverMapUrl)) {
        await launchUrl(naverMapUrl, mode: LaunchMode.externalApplication);
      } 
      // 둘 다 없으면 구글맵(또는 웹브라우저) 시도
      else {
        await launchUrl(googleMapUrl, mode: LaunchMode.externalApplication);
      }

      // 💡 [2단계 적용] 지도 앱으로 넘어간 직후, 폰 상단에 푸시 알림처럼 행동 지침 띄워주기 (SnackBar 활용)
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text("🚨 대피 지침 (도착 시)", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.white)),
                const SizedBox(height: 4),
                Text("편의점 안으로 들어가 점원에게 '위험해요, 112 비상벨 눌러주세요!'라고 외치세요.", style: TextStyle(color: Colors.red[100], fontSize: 14)),
              ],
            ),
            backgroundColor: Colors.red[900],
            duration: const Duration(seconds: 10), // 길게 띄워둠
            behavior: SnackBarBehavior.floating,
            margin: EdgeInsets.only(bottom: MediaQuery.of(context).size.height - 150, left: 20, right: 20), // 화면 상단에 띄우기
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('지도 앱을 실행할 수 없습니다.')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentUserUid = FirebaseAuth.instance.currentUser?.uid;

    bool isSafeZone = meetupData?['isSafeZone'] ?? false;
    String safeZoneName = meetupData?['safeZoneName'] ?? '안심지킴이집';
    int safeZoneDistance = meetupData?['safeZoneDistance'] ?? 0;
    
    // 안심지킴이집의 실제 좌표 (없으면 모임 좌표 사용)
    double destLat = meetupData?['lat'] ?? 0.0;
    double destLng = meetupData?['lng'] ?? 0.0;

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
            Text(
              gathering.title,
              style: const TextStyle(fontSize: 26, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            
            // 🛡️ 안심 구역 대피소 정보 카드 & 🚨 SOS 버튼
            if (isSafeZone) ...[
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: Colors.blue[50],
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.blueAccent.withOpacity(0.3)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.security, color: Colors.blueAccent, size: 28),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Text(
                                '🛡️ 인근 안심 대피소 인증 구역',
                                style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blueAccent, fontSize: 13),
                              ),
                              const SizedBox(width: 4),
                              // 💡 [3단계 적용] 툴팁 추가
                              Tooltip(
                                message: '여성안심지킴이집이란? 24시간 불이 켜져 있고, 112 경찰 상황실과 즉시 연결되는 카운터 비상벨이 설치된 편의점입니다.',
                                triggerMode: TooltipTriggerMode.tap,
                                showDuration: const Duration(seconds: 4),
                                decoration: BoxDecoration(color: Colors.black87, borderRadius: BorderRadius.circular(8)),
                                child: const Icon(Icons.help_outline, size: 16, color: Colors.grey),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '반경 ${safeZoneDistance}m 내에 대피소($safeZoneName) 위치',
                            style: const TextStyle(color: Colors.black87, fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                    // 🚨 [1단계 적용] 화면을 가리지 않는 컴팩트한 SOS 대피 버튼
                    ElevatedButton.icon(
                      onPressed: () => _launchEmergencyNavigation(context, destLat, destLng, safeZoneName),
                      icon: const Icon(Icons.run_circle, color: Colors.white, size: 18),
                      label: const Text("대피", style: TextStyle(fontWeight: FontWeight.bold)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.redAccent,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
            ],

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
            
            AiMatchingCard(
              meetingTitle: gathering.title, 
              meetingDescription: gathering.description,
            ),
            
            const SizedBox(height: 24),

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

                  final bool isJoined = currentUserUid != null && participants.contains(currentUserUid);

                  return Column(
                    children: [
                      Expanded(
                        child: participants.isEmpty
                            ? const Center(child: Text('아직 참여자가 없습니다.', style: TextStyle(color: Colors.grey)))
                            : ListView.separated(
                                itemCount: participants.length,
                                separatorBuilder: (_, __) => const Divider(),
                                itemBuilder: (context, index) {
                                  final uid = participants[index];
                                  
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
                                      final meetingCount = userData['meetingCount'] ?? 0;

                                      return ListTile(
                                        contentPadding: EdgeInsets.zero,
                                        leading: CircleAvatar(
                                          backgroundColor: Colors.green[50],
                                          child: const Icon(Icons.person, color: Colors.green),
                                        ),
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

                      ElevatedButton(
                        onPressed: currentUserUid == null ? null : () async {
                          try {
                            if (isJoined) {
                              await doc.reference.update({
                                'participants': FieldValue.arrayRemove([currentUserUid]),
                                'currentParticipants': FieldValue.increment(-1),
                              });
                              if (context.mounted) _showSnackBar(context, "참여를 취소했습니다.", Colors.grey);
                            } else {
                              await doc.reference.update({
                                'participants': FieldValue.arrayUnion([currentUserUid]),
                                'currentParticipants': FieldValue.increment(1),
                              });
                              
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

  Widget _buildBadge(String text, MaterialColor color) {
    if (text == '비공개') return const SizedBox.shrink(); 
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
      final user = FirebaseAuth.instance.currentUser;
      String myMbti = 'ENFP'; 
      if (user != null) {
        final doc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
        myMbti = (doc.data() as Map<String, dynamic>?)?['mbti'] ?? 'ENFP';
      }

      final model = GenerativeModel(
        model: 'gemini-3.6-flash',
        apiKey: dotenv.env['GEMINI_API_KEY'] ?? '',
      );

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