import 'dart:async';

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'dart:convert';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:google_generative_ai/google_generative_ai.dart';

import '../models/gathering_model.dart';
import '../services/chat_service.dart';
import '../services/route_service.dart';
import '../screens/route_guide_screen.dart';

class GatheringDetailScreen extends StatelessWidget {
  final Gathering gathering;
  final Map<String, dynamic>? meetupData;
  final String? meetingId;

  const GatheringDetailScreen({
    super.key,
    required this.gathering,
    this.meetupData,
    this.meetingId,
  });

  double _readCoordinate(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '') ?? 0.0;
  }

  Query<Map<String, dynamic>> _meetingQuery() {
    final collection = FirebaseFirestore.instance.collection('meetings');
    if (meetingId != null && meetingId!.isNotEmpty) {
      return collection.where(FieldPath.documentId, isEqualTo: meetingId);
    }
    return collection.where('title', isEqualTo: gathering.title).limit(1);
  }

  Future<void> _openInAppRoute(
    BuildContext context, {
    required double latitude,
    required double longitude,
    required String destinationName,
    required RouteTravelMode mode,
  }) async {
    if (latitude == 0 || longitude == 0) {
      _showSnackBar(context, '모임 장소 좌표가 없어 길안내를 시작할 수 없습니다.', Colors.orange);
      return;
    }

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => RouteGuideScreen(
          destination: LatLng(latitude, longitude),
          destinationName: destinationName,
          mode: mode,
        ),
      ),
    );
  }

  Widget _buildPrivateLocationSection({
    required BuildContext context,
    required DocumentReference<Map<String, dynamic>> meetingRef,
    required double latitude,
    required double longitude,
    required String neighborhood,
  }) {
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: meetingRef.collection('private').doc('location').snapshots(),
      builder: (context, snapshot) {
        final privateData = snapshot.data?.data();
        final String address = (privateData?['address'] ?? '').toString().trim();
        final String destinationName = address.isNotEmpty ? address : neighborhood;
        final bool hasDestination = latitude != 0 && longitude != 0;

        return Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.green[50],
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.green.withOpacity(0.25)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                children: [
                  Icon(Icons.location_on, color: Colors.green),
                  SizedBox(width: 7),
                  Text('모임 장소 주소', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                ],
              ),
              const SizedBox(height: 9),
              const Text(
                '모임 참여가 완료되었습니다. 현재 위치에서 모임 장소까지 앱 안에서 길안내를 시작할 수 있습니다.',
                style: TextStyle(fontSize: 12, color: Colors.black54, height: 1.35),
              ),
              const SizedBox(height: 8),
              if (snapshot.hasError)
                const Text(
                  '주소를 불러오지 못했습니다. Firestore 보안 규칙에서 참여자 주소 읽기 권한을 확인해주세요.',
                  style: TextStyle(fontSize: 13, color: Colors.redAccent, height: 1.4),
                )
              else if (snapshot.connectionState == ConnectionState.waiting && privateData == null)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 6),
                  child: LinearProgressIndicator(minHeight: 2),
                )
              else if (address.isNotEmpty)
                Text(address, style: const TextStyle(fontSize: 14, height: 1.45))
              else
                const Text(
                  '저장된 상세 주소가 없습니다. 아래 길찾기는 모임 좌표를 기준으로 실행됩니다.',
                  style: TextStyle(fontSize: 13, color: Colors.black54, height: 1.4),
                ),
              if (address.isEmpty && neighborhood.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text('동네 정보: $neighborhood', style: const TextStyle(color: Colors.black54, fontSize: 12)),
              ],
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: hasDestination
                          ? () => _openInAppRoute(
                                context,
                                latitude: latitude,
                                longitude: longitude,
                                destinationName: destinationName,
                                mode: RouteTravelMode.walking,
                              )
                          : null,
                      icon: const Icon(Icons.directions_walk),
                      label: const Text('도보 길안내 시작'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.green[800],
                        side: BorderSide(color: Colors.green.shade300),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: hasDestination
                          ? () => _openInAppRoute(
                                context,
                                latitude: latitude,
                                longitude: longitude,
                                destinationName: destinationName,
                                mode: RouteTravelMode.cycling,
                              )
                          : null,
                      icon: const Icon(Icons.directions_bike),
                      label: const Text('자전거 길안내 시작'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.green[800],
                        side: BorderSide(color: Colors.green.shade300),
                      ),
                    ),
                  ),
                ],
              ),
              if (!hasDestination)
                const Padding(
                  padding: EdgeInsets.only(top: 8),
                  child: Text('모임 좌표가 없어 길안내를 사용할 수 없습니다.', style: TextStyle(color: Colors.red, fontSize: 12)),
                ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _launchEmergencyNavigation(
    BuildContext context,
    double latitude,
    double longitude,
    String destinationName,
  ) async {
    if (latitude == 0 || longitude == 0) {
      _showSnackBar(context, '대피 장소 좌표가 없습니다.', Colors.orange);
      return;
    }

    final kakaoUrl = Uri.parse(
      'kakaomap://route?ep=$latitude,$longitude&by=foot',
    );
    final naverUrl = Uri.parse(
      'nmap://route/walk?dlat=$latitude&dlng=$longitude'
      '&dname=${Uri.encodeComponent(destinationName)}'
      '&appname=com.example.hyper_local_project',
    );
    final googleUrl = Uri.parse(
      'https://www.google.com/maps/dir/?api=1'
      '&destination=$latitude,$longitude&travelmode=walking',
    );

    try {
      var launched = await launchUrl(
        kakaoUrl,
        mode: LaunchMode.externalApplication,
      );
      if (!launched) {
        launched = await launchUrl(
          naverUrl,
          mode: LaunchMode.externalApplication,
        );
      }
      if (!launched) {
        launched = await launchUrl(
          googleUrl,
          mode: LaunchMode.externalApplication,
        );
      }
      if (!launched && context.mounted) {
        _showSnackBar(context, '지도 앱을 실행할 수 없습니다.', Colors.red);
      }
    } catch (e) {
      if (context.mounted) {
        _showSnackBar(context, '지도 앱 실행에 실패했습니다.', Colors.red);
      }
    }
  }

  void _showSnackBar(BuildContext context, String message, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: color,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _toggleParticipation({
    required BuildContext context,
    required DocumentReference<Map<String, dynamic>> meetingRef,
    required Map<String, dynamic> data,
    required List participants,
    required bool isJoined,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      _showSnackBar(context, '로그인 후 이용할 수 있습니다.', Colors.orange);
      return;
    }

    final creatorId = (data['creatorId'] ?? '').toString();
    if (creatorId == user.uid) {
      _showSnackBar(context, '모임 방장은 본인 모임에서 나갈 수 없습니다.', Colors.orange);
      return;
    }

    try {
      if (isJoined) {
        await FirebaseFirestore.instance.runTransaction((transaction) async {
          final snapshot = await transaction.get(meetingRef);
          if (!snapshot.exists) throw Exception('모임이 이미 삭제되었습니다.');

          final latest = snapshot.data() ?? <String, dynamic>{};
          final latestParticipants = latest['participants'] is List
              ? List<dynamic>.from(latest['participants'] as List)
              : <dynamic>[];
          if (!latestParticipants.contains(user.uid)) return;

          final current = (latest['currentParticipants'] as num?)?.toInt() ??
              latestParticipants.length;
          transaction.update(meetingRef, {
            'participants': FieldValue.arrayRemove([user.uid]),
            'currentParticipants': current > 0 ? current - 1 : 0,
          });
        });

        try {
          await ChatService().leaveRoom(meetingRef.id);
        } catch (chatError) {
          debugPrint('[모임 나가기 - 채팅방 멤버 정리 실패] $chatError');
        }
        _showSnackBar(context, '모임 참여를 취소했습니다.', Colors.grey);
        return;
      }

      final joinStatus = await FirebaseFirestore.instance.runTransaction<String>((transaction) async {
        final snapshot = await transaction.get(meetingRef);
        if (!snapshot.exists) return 'missing';

        final latest = snapshot.data() ?? <String, dynamic>{};
        final latestParticipants = latest['participants'] is List
            ? List<dynamic>.from(latest['participants'] as List)
            : <dynamic>[];

        if (latest['creatorId'] == user.uid || latestParticipants.contains(user.uid)) {
          return 'already_joined';
        }

        DateTime? parseDate(dynamic value) {
          if (value is Timestamp) return value.toDate();
          if (value is DateTime) return value;
          if (value is String) return DateTime.tryParse(value);
          return null;
        }

        final now = DateTime.now();
        final deadline = parseDate(latest['deadline']);
        final expireAt = parseDate(latest['expireAt']);
        if ((deadline != null && !deadline.isAfter(now)) ||
            (expireAt != null && !expireAt.isAfter(now))) {
          return 'expired';
        }

        final current = (latest['currentParticipants'] as num?)?.toInt() ??
            latestParticipants.length;
        final max = (latest['maxParticipants'] as num?)?.toInt() ?? 4;
        if (current >= max) return 'full';

        transaction.update(meetingRef, {
          'participants': <dynamic>[...latestParticipants, user.uid],
          'currentParticipants': current + 1,
        });
        return 'joined';
      });

      if (joinStatus == 'full') {
        _showSnackBar(context, '모임 정원이 모두 찼습니다.', Colors.orange);
        return;
      }
      if (joinStatus == 'expired') {
        _showSnackBar(context, '모임 마감 시간이 지나 참여할 수 없습니다.', Colors.orange);
        return;
      }
      if (joinStatus == 'missing') {
        _showSnackBar(context, '이미 삭제된 모임입니다.', Colors.orange);
        return;
      }

      final latest = await meetingRef.get();
      final latestData = latest.data() ?? data;
      var chatConnected = true;
      try {
        await ChatService().joinRoom(
          meetingId: meetingRef.id,
          meetingData: latestData,
        );
      } catch (chatError) {
        chatConnected = false;
        debugPrint('[모임 채팅방 참여] $chatError');
      }

      try {
        await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
          'meetingCount': FieldValue.increment(1),
        }, SetOptions(merge: true));
      } catch (profileError) {
        debugPrint('[모임 참가 횟수 갱신 실패] $profileError');
      }

      if (joinStatus == 'already_joined') {
        _showSnackBar(context, '이미 참여한 모임입니다.', Colors.green);
      } else if (chatConnected) {
        _showSnackBar(
          context,
          '🎉 모임 참여가 완료되었습니다! 아래에서 도보·자전거 길안내를 선택하세요.',
          Colors.green,
        );
      } else {
        _showSnackBar(
          context,
          '모임 참여는 완료됐지만 채팅방 연결에 실패했습니다. 채팅 탭에서 다시 확인해 주세요.',
          Colors.orange,
        );
      }
      // 상세 화면은 닫지 않습니다. Firestore Stream이 참가 상태를 갱신하면
      // 위쪽에 참여자 전용 주소와 도보/자전거 길안내 버튼이 표시됩니다.
    } catch (e) {
      _showSnackBar(context, '참여 처리 중 오류가 발생했습니다: $e', Colors.red);
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentUserUid = FirebaseAuth.instance.currentUser?.uid;

    return Scaffold(
      appBar: AppBar(
        title: const Text('모임 상세 정보', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.green,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: _meetingQuery().snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting && meetupData == null) {
            return const Center(child: CircularProgressIndicator(color: Colors.green));
          }

          Map<String, dynamic> data = meetupData ?? <String, dynamic>{};
          DocumentReference<Map<String, dynamic>>? meetingRef;
          if (snapshot.hasData && snapshot.data!.docs.isNotEmpty) {
            final doc = snapshot.data!.docs.first;
            data = doc.data();
            meetingRef = doc.reference;
          } else if (meetingId != null && meetingId!.isNotEmpty) {
            meetingRef = FirebaseFirestore.instance.collection('meetings').doc(meetingId);
          }

          final participants = data['participants'] as List? ?? <dynamic>[];
          final creatorId = (data['creatorId'] ?? '').toString();
          final bool isJoined = currentUserUid != null &&
              (participants.contains(currentUserUid) || creatorId == currentUserUid);

          final double destinationLat = _readCoordinate(data['lat']);
          final double destinationLng = _readCoordinate(data['lng']);
          final bool hasDestination = destinationLat != 0 && destinationLng != 0;
          final String neighborhood =
              (data['dong'] ?? data['region'] ?? gathering.location).toString();

          final bool isSafeZone = data['isSafeZone'] == true;
          final String safeZoneName = (data['safeZoneName'] ?? '안심지킴이집').toString();
          final int safeZoneDistance = (data['safeZoneDistance'] as num?)?.toInt() ?? 0;

          return SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
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
                      '모임 시간: ${gathering.date}',
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // 주소는 private 서브컬렉션에서 읽습니다. 방장/참여자만 접근할 수 있습니다.
                if (isJoined && meetingRef != null) ...[
                  _buildPrivateLocationSection(
                    context: context,
                    meetingRef: meetingRef,
                    latitude: destinationLat,
                    longitude: destinationLng,
                    neighborhood: neighborhood,
                  ),
                ] else ...[
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: Colors.grey[100],
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Text(
                      '정확한 모임 장소 주소와 길찾기는 모임에 참여한 후 확인할 수 있습니다.',
                      style: TextStyle(color: Colors.black54, height: 1.4),
                    ),
                  ),
                ],

                if (isSafeZone) ...[
                  const SizedBox(height: 16),
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
                              const Text(
                                '인근 안심지킴이집 확인',
                                style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blueAccent, fontSize: 13),
                              ),
                              const SizedBox(height: 4),
                              Text('반경 ${safeZoneDistance}m 내에 $safeZoneName 위치'),
                            ],
                          ),
                        ),
                        ElevatedButton.icon(
                          onPressed: () => _launchEmergencyNavigation(
                            context,
                            destinationLat,
                            destinationLng,
                            safeZoneName,
                          ),
                          icon: const Icon(Icons.run_circle, size: 18),
                          label: const Text('대피'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.redAccent,
                            foregroundColor: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],

                const SizedBox(height: 20),
                const Divider(thickness: 1.5),
                const SizedBox(height: 10),
                const Text('모임 설명', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.grey[100],
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(gathering.description, style: const TextStyle(fontSize: 16, height: 1.5)),
                ),

                AiMatchingCard(
                  meetingTitle: gathering.title,
                  meetingDescription: gathering.description,
                ),

                const SizedBox(height: 10),
                const Text('참여자 프로필', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 12),
                if (participants.isEmpty)
                  const Center(
                    child: Padding(
                      padding: EdgeInsets.all(16),
                      child: Text('아직 참여자가 없습니다.', style: TextStyle(color: Colors.grey)),
                    ),
                  )
                else
                  ListView.separated(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: participants.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final uid = participants[index].toString();
                      return FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                        future: FirebaseFirestore.instance.collection('users').doc(uid).get(),
                        builder: (context, userSnapshot) {
                          if (!userSnapshot.hasData) {
                            return const ListTile(title: Text('유저 정보 불러오는 중...'));
                          }
                          final userData = userSnapshot.data!.data();
                          if (userData == null) return const ListTile(title: Text('알 수 없는 유저'));

                          final nickname = (userData['displayName'] ?? '이름 없음').toString();
                          final ageGroup = (userData['ageGroup'] ?? '비공개').toString();
                          final gender = (userData['gender'] ?? '비공개').toString();
                          final mbti = (userData['mbti'] ?? '비공개').toString();
                          final mannerVolt = userData['mannerVolt'] ?? 0;
                          final meetingCount = (userData['meetingCount'] as num?)?.toInt() ?? 0;

                          return ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: CircleAvatar(
                              backgroundColor: Colors.green[50],
                              child: const Icon(Icons.person, color: Colors.green),
                            ),
                            title: Row(
                              children: [
                                Flexible(
                                  child: Text(nickname, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.bold)),
                                ),
                                if (meetingCount <= 3) ...[
                                  const SizedBox(width: 6),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: Colors.green[100],
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Text(
                                      '🌱 동네 뉴비',
                                      style: TextStyle(fontSize: 10, color: Colors.green[800], fontWeight: FontWeight.bold),
                                    ),
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

                const SizedBox(height: 20),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.people_alt, color: Colors.green),
                    const SizedBox(width: 8),
                    Text(
                      '현재 ${participants.length}명이 모였습니다!',
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.green),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                if (meetingRef != null && creatorId == currentUserUid)
                  const SizedBox.shrink()
                else if (meetingRef != null)
                  ElevatedButton(
                    onPressed: currentUserUid == null
                        ? null
                        : () => _toggleParticipation(
                              context: context,
                              meetingRef: meetingRef!,
                              data: data,
                              participants: participants,
                              isJoined: isJoined,
                            ),
                    style: ElevatedButton.styleFrom(
                      minimumSize: const Size(double.infinity, 55),
                      backgroundColor: isJoined ? Colors.grey[400] : Colors.green,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    ),
                    child: Text(
                      isJoined ? '참여 취소하기' : '⚡ 이 번개 참여하기',
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                  )
                else
                  const Text(
                    '모임 정보를 불러올 수 없어 참여 기능을 사용할 수 없습니다.',
                    style: TextStyle(color: Colors.redAccent),
                  ),
              ],
            ),
          );
        },
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
}

class AiMatchingCard extends StatefulWidget {
  final String meetingTitle;
  final String meetingDescription;

  const AiMatchingCard({
    super.key,
    required this.meetingTitle,
    required this.meetingDescription,
  });

  @override
  State<AiMatchingCard> createState() => _AiMatchingCardState();
}

class _AiMatchingCardState extends State<AiMatchingCard> {
  bool _isLoading = false;
  int _score = 0;
  String _reason = '';
  String _errorMessage = '';

  @override
  void initState() {
    super.initState();
    _analyzeMatch();
  }

  Future<void> _analyzeMatch() async {
    if (_isLoading) return;

    setState(() {
      _isLoading = true;
      _errorMessage = '';
      _reason = '';
      _score = 0;
    });

    try {
      // 1. Gemini API 키 확인
      final apiKey = dotenv.env['GEMINI_API_KEY']?.trim() ?? '';
      if (apiKey.isEmpty) {
        throw const _AiMatchingException(
          'Gemini API 키를 찾을 수 없습니다. .env 파일에 GEMINI_API_KEY가 설정되어 있는지 확인해 주세요.',
        );
      }

      // 2. 로그인한 사용자의 MBTI 조회
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        throw const _AiMatchingException('로그인 정보를 확인할 수 없습니다. 다시 로그인해 주세요.');
      }

      final userSnapshot = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get()
          .timeout(const Duration(seconds: 10));

      final userData = userSnapshot.data();
      final myMbti = (userData?['mbti'] ?? '').toString().trim();
      final mbtiForPrompt = myMbti.isEmpty || myMbti == '비공개'
          ? '미설정'
          : myMbti.toUpperCase();

      // 이 프로젝트의 다른 AI 기능과 동일한 Gemini 모델 사용
      final model = GenerativeModel(
        model: 'gemini-3.5-flash-lite',
        apiKey: apiKey,
        generationConfig: GenerationConfig(
          responseMimeType: 'application/json',
          maxOutputTokens: 220,
          temperature: 0.3,
        ),
      );

      final prompt = '''
너는 동네 모임을 추천하는 친근한 AI 매칭 도우미야.
사용자 MBTI: $mbtiForPrompt
참여하려는 모임 제목: ${widget.meetingTitle}
모임 설명: ${widget.meetingDescription}

이 모임이 사용자에게 얼마나 잘 맞을지 참고용 점수를 1부터 100 사이 정수로 평가해.
MBTI가 미설정이면 MBTI를 임의로 추측하지 말고 모임 제목과 설명을 바탕으로 일반적인 추천 의견을 작성해.
점수의 이유는 한국어로 자연스럽고 간결하게 1~2문장으로 작성해.
실제 성격이나 참여 결과를 단정하지 말고 재미와 참고를 위한 추천임을 고려해.
마크다운이나 코드 블록 없이 다음 JSON 객체 하나만 반환해.
{"score": 85, "reason": "관심사와 잘 맞아 즐겁게 참여할 수 있을 것 같아요."}
''';

      final response = await model
          .generateContent([Content.text(prompt)])
          .timeout(const Duration(seconds: 25));

      final responseText = response.text?.trim() ?? '';
      if (responseText.isEmpty) {
        throw const FormatException(
          'Gemini에서 빈 응답을 받았습니다. 잠시 후 다시 시도해 주세요.',
        );
      }

      // JSON 앞뒤에 불필요한 문장이 포함되어도 JSON 객체만 추출
      final jsonStart = responseText.indexOf('{');
      final jsonEnd = responseText.lastIndexOf('}');
      if (jsonStart < 0 || jsonEnd <= jsonStart) {
        throw const FormatException(
          'AI 응답에서 결과 데이터를 찾지 못했습니다. 다시 시도해 주세요.',
        );
      }

      final jsonText = responseText.substring(jsonStart, jsonEnd + 1);
      final decoded = jsonDecode(jsonText);
      if (decoded is! Map) {
        throw const FormatException('AI 응답 형식이 올바르지 않습니다.');
      }

      final scoreValue = decoded['score'];
      final parsedScore = scoreValue is num
          ? scoreValue.toInt()
          : int.tryParse(scoreValue?.toString() ?? '');
      final generatedReason = (decoded['reason'] ?? '').toString().trim();

      if (parsedScore == null || generatedReason.isEmpty) {
        throw const FormatException(
          'AI 분석 결과에 점수 또는 설명이 누락되었습니다. 다시 시도해 주세요.',
        );
      }

      if (!mounted) return;
      setState(() {
        _score = parsedScore.clamp(1, 100).toInt();
        _reason = generatedReason;
        _isLoading = false;
        _errorMessage = '';
      });
    } on TimeoutException {
      _setError('AI 분석 응답 시간이 초과되었습니다. 인터넷 연결을 확인한 뒤 다시 시도해 주세요.');
    } on _AiMatchingException catch (error) {
      _setError(error.message);
    } catch (error, stackTrace) {
      debugPrint('[AI 성향 분석 실패] $error');
      debugPrintStack(stackTrace: stackTrace);

      final raw = error.toString();
      final lower = raw.toLowerCase();
      String message;

      if (raw.contains('429') ||
          lower.contains('quota') ||
          lower.contains('resource_exhausted')) {
        message = 'Gemini API 사용량 한도에 도달했습니다. 잠시 후 다시 시도해 주세요.';
      } else if (raw.contains('401') ||
          raw.contains('403') ||
          lower.contains('api key not valid') ||
          lower.contains('permission_denied')) {
        message = 'Gemini API 인증에 실패했습니다. .env의 API 키와 사용 권한을 확인해 주세요.';
      } else if (raw.contains('404') || lower.contains('not found')) {
        message = 'Gemini 모델 또는 API 주소를 찾을 수 없습니다. 모델 설정을 확인해 주세요.';
      } else if (error is FormatException) {
        message = error.message;
      } else if (lower.contains('socket') ||
          lower.contains('network') ||
          lower.contains('failed host lookup') ||
          lower.contains('clientexception')) {
        message = '네트워크 연결에 실패했습니다. 인터넷 연결을 확인해 주세요.';
      } else {
        final detail = raw.length > 160 ? '${raw.substring(0, 160)}…' : raw;
        message = 'AI 분석에 실패했습니다. 아래 오류를 확인해 주세요.\n$detail';
      }

      _setError(message);
    }
  }

  void _setError(String message) {
    if (!mounted) return;
    setState(() {
      _isLoading = false;
      _errorMessage = message;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.purple.shade50, Colors.blue.shade50],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.purple.withOpacity(0.2)),
        boxShadow: const [
          BoxShadow(
            color: Colors.black12,
            blurRadius: 8,
            offset: Offset(0, 3),
          ),
        ],
      ),
      child: _isLoading
          ? const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.purple,
                  ),
                ),
                SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'AI가 회원님과의 모임 궁합을 분석하고 있습니다...',
                    style: TextStyle(
                      color: Colors.purple,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            )
          : _errorMessage.isNotEmpty
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(
                      children: [
                        Icon(Icons.error_outline, color: Colors.red),
                        SizedBox(width: 8),
                        Text(
                          'AI 스마트 매칭',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                            color: Colors.black87,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Text(
                      _errorMessage,
                      style: const TextStyle(
                        color: Colors.red,
                        fontSize: 13,
                        height: 1.45,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Align(
                      alignment: Alignment.centerRight,
                      child: OutlinedButton.icon(
                        onPressed: _analyzeMatch,
                        icon: const Icon(Icons.refresh, size: 18),
                        label: const Text('다시 분석하기'),
                      ),
                    ),
                  ],
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.auto_awesome, color: Colors.purple),
                        const SizedBox(width: 8),
                        const Text(
                          'AI 스마트 매칭',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                            color: Colors.black87,
                          ),
                        ),
                        const Spacer(),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: _score >= 80
                                ? Colors.green
                                : (_score >= 50 ? Colors.orange : Colors.red),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            '$_score점',
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(
                      _reason,
                      style: const TextStyle(
                        fontSize: 14,
                        color: Colors.black87,
                        height: 1.5,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      '※ MBTI 및 모임 정보를 바탕으로 한 참고용 추천입니다.',
                      style: TextStyle(fontSize: 11, color: Colors.black45),
                    ),
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton.icon(
                        onPressed: _analyzeMatch,
                        icon: const Icon(Icons.refresh, size: 16),
                        label: const Text('다시 분석'),
                      ),
                    ),
                  ],
                ),
    );
  }
}

class _AiMatchingException implements Exception {
  final String message;
  const _AiMatchingException(this.message);

  @override
  String toString() => message;
}
