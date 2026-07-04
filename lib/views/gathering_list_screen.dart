import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart'; // 추가
import '../models/gathering_model.dart';
import 'gathering_detail_screen.dart';

class GatheringListScreen extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("우리 동네 번개 목록"),
        backgroundColor: Colors.green, // 지도와 색상 통일
      ),
      // StreamBuilder를 사용해 Firebase 데이터를 실시간으로 가져옵니다.
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance.collection('meetings').snapshots(),
        builder: (context, snapshot) {
          if (!snapshot.hasData)
            return const Center(child: CircularProgressIndicator());

          final docs = snapshot.data!.docs;

          return ListView.builder(
            itemCount: docs.length,
            itemBuilder: (context, index) {
              final data = docs[index].data() as Map<String, dynamic>;

              // Firebase 데이터를 모델 객체로 변환
              final gathering = Gathering(
                title: data['title'] ?? '제목 없음',
                location: "지도 표시 지점", // 위도/경도 기반 주소 변환은 추후 추가
                date: data['time'] ?? '시간 미정',
                description: "지도에서 등록된 번개 모임입니다.",
              );

              return ListTile(
                leading: const Icon(Icons.flash_on, color: Colors.orange),
                title: Text(gathering.title),
                subtitle: Text("시간: ${gathering.date}"),
                // 오른쪽에 참여 인원수 표시
                trailing: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.blue[50],
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    // 데이터에서 participants 길이를 가져와 표시
                    "${(docs[index].data() as Map<String, dynamic>)['participants']?.length ?? 0}명",
                    style: const TextStyle(
                      color: Colors.blue,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) =>
                          GatheringDetailScreen(gathering: gathering),
                    ),
                  );
                },
              );
            },
          );
        },
      ),
    );
  }
}
