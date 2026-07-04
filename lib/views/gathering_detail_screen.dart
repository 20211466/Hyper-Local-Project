import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/gathering_model.dart';

class GatheringDetailScreen extends StatelessWidget {
  final Gathering gathering;

  const GatheringDetailScreen({super.key, required this.gathering});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("모임 정보"), backgroundColor: Colors.green),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 1. 모임 기본 정보
            Text(
              gathering.title,
              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                const Icon(Icons.access_time, size: 18, color: Colors.grey),
                const SizedBox(width: 5),
                Text("시간: ${gathering.date}"),
              ],
            ),
            const Divider(height: 30),

            // 2. 모임 상세 설명
            const Text(
              "모임 설명",
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),
            Text(gathering.description),

            const Spacer(),

            // 3. 실시간 참여 인원 및 참여/취소 버튼 영역
            StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('meetings')
                  .where('title', isEqualTo: gathering.title)
                  .snapshots(),
              builder: (context, snapshot) {
                if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                  return const Center(child: Text("데이터를 불러오는 중..."));
                }

                final doc = snapshot.data!.docs.first;
                final data = doc.data() as Map<String, dynamic>;
                final List participants = data['participants'] ?? [];

                // 내 참여 여부 확인 (현재는 '익명 참여자'로 고정)
                final bool isJoined = participants.contains('익명 참여자');

                return Column(
                  children: [
                    // 참여 인원수 표시
                    Padding(
                      padding: const EdgeInsets.only(bottom: 16.0),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.people, color: Colors.blue),
                          const SizedBox(width: 8),
                          Text(
                            "현재 ${participants.length}명이 참여 중입니다!",
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Colors.blue,
                            ),
                          ),
                        ],
                      ),
                    ),

                    // 참여/취소 버튼
                    ElevatedButton(
                      onPressed: () async {
                        try {
                          if (isJoined) {
                            // 취소 로직
                            await doc.reference.update({
                              'participants': FieldValue.arrayRemove([
                                '익명 참여자',
                              ]),
                            });
                            if (context.mounted)
                              _showSnackBar(context, "참여를 취소했습니다.");
                          } else {
                            // 참여 로직
                            await doc.reference.update({
                              'participants': FieldValue.arrayUnion(['익명 참여자']),
                            });
                            if (context.mounted)
                              _showSnackBar(context, "참여가 완료되었습니다!");
                          }
                        } catch (e) {
                          if (context.mounted)
                            _showSnackBar(context, "오류 발생: $e");
                        }
                      },
                      style: ElevatedButton.styleFrom(
                        minimumSize: const Size(double.infinity, 55),
                        backgroundColor: isJoined
                            ? Colors.grey[400]
                            : Colors.orange,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: Text(
                        isJoined ? "참여 취소하기" : "참여하기",
                        style: const TextStyle(
                          fontSize: 18,
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  // 스낵바 표시 함수 (클래스 내부, build 메서드 외부에 위치)
  void _showSnackBar(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        duration: const Duration(seconds: 1),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}
