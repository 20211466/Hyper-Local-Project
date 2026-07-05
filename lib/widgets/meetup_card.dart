import 'package:flutter/material.dart';

class MeetupCard extends StatelessWidget {
  final Map<String, dynamic> meetupData;

  const MeetupCard({super.key, required this.meetupData});

  @override
  Widget build(BuildContext context) {
    // 파이어베이스 필드 데이터 안전하게 추출
    final title = meetupData['title'] ?? '제목 없음';
    final category = meetupData['category'] ?? '기타';
    final location = meetupData['location'] ?? '지도 표시 지점';
    
    // 💡 인원수 필드 명칭을 'maxParticipants'로 정확하게 일치시켜 0명 고정 문제 해결
    final int currentParticipants = meetupData['currentParticipants'] ?? 1;
    final int maxParticipants = meetupData['maxParticipants'] ?? 4;
    final isFull = currentParticipants >= maxParticipants;

    // 💡 카테고리별 맞춤형 시각 요소 지정 (식사는 맛있는 음식으로 변경!)
    Widget categoryIcon;
    switch (category) {
      case '식사':
        categoryIcon = const Center(child: Text('🍔', style: TextStyle(fontSize: 24)));
        break;
      case '운동':
        categoryIcon = const Center(child: Text('⚽', style: TextStyle(fontSize: 24)));
        break;
      case '공부':
        categoryIcon = const Center(child: Text('📚', style: TextStyle(fontSize: 24)));
        break;
      case '게임':
        categoryIcon = const Center(child: Text('🎮', style: TextStyle(fontSize: 24)));
        break;
      case '산책':
        categoryIcon = const Center(child: Text('🐕', style: TextStyle(fontSize: 24)));
        break;
      default:
        categoryIcon = const Center(child: Text('⚡', style: TextStyle(fontSize: 24)));
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: const [
          BoxShadow(color: Colors.black12, blurRadius: 8, offset: Offset(0, 3)),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: Colors.green[50],
              borderRadius: BorderRadius.circular(12),
            ),
            child: categoryIcon,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Text(
                  '$category · $location',
                  style: const TextStyle(color: Colors.black54, fontSize: 13),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '$currentParticipants/$maxParticipants 명',
            style: TextStyle(
              color: isFull ? Colors.red : Colors.green,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}