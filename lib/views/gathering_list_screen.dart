import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'gathering_detail_screen.dart';
import '../models/gathering_model.dart'; 
import '../widgets/meetup_card.dart';

class GatheringListScreen extends StatelessWidget {
  const GatheringListScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("우리 동네 번개 목록"),
        backgroundColor: Colors.green,
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance.collection('meetings').snapshots(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final docs = snapshot.data!.docs;

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: docs.length,
            itemBuilder: (context, index) {
              final doc = docs[index];
              final data = doc.data();

              // 기존 상세 화면(GatheringDetailScreen) 호환성을 위한 모델 객체 생성
              final gathering = Gathering(
                title: data['title'] ?? '제목 없음',
                location: data['location'] ?? "지도 표시 지점",
                date: data['time'] ?? '시간 미정',
                description: data['description'] ?? "지도에서 등록된 번개 모임입니다.",
              );

              return GestureDetector(
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) =>
                          GatheringDetailScreen(gathering: gathering),
                    ),
                  );
                },
                // 💡 파이어베이스 원본 데이터를 그대로 전달하여 카드 내부에서 정확하게 매칭시킵니다.
                child: MeetupCard(meetupData: data),
              );
            },
          );
        },
      ),
    );
  }
}