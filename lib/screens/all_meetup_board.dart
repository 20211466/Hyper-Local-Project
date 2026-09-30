import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geolocator/geolocator.dart';

class AllMeetupBoardScreen extends StatefulWidget {
  @override
  _AllMeetupBoardScreenState createState() => _AllMeetupBoardScreenState();
}

class _AllMeetupBoardScreenState extends State<AllMeetupBoardScreen> {
  final double MAX_DISTANCE_METERS = 8000.0; // 최대 허용 반경 (8km)

  // 사용자의 현재 위치를 가져와서 모임 장소와 거리를 계산하는 함수
  Future<void> _checkDistanceAndJoin(BuildContext context, DocumentSnapshot meetupDoc) async {
    try {
      // 로딩 창 띄우기 (위치 계산하는 동안 대기)
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => Center(child: CircularProgressIndicator()),
      );

      // 1. 사용자 현재 위치 가져오기
      Position userPosition = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );

      // 2. 모임의 위치 정보 가져오기 (Firestore의 GeoPoint 기준)
      GeoPoint meetupLocation = meetupDoc['location'];

      // 3. 거리 계산 (단위: 미터)
      double distanceInMeters = Geolocator.distanceBetween(
        userPosition.latitude,
        userPosition.longitude,
        meetupLocation.latitude,
        meetupLocation.longitude,
      );

      Navigator.pop(context); // 로딩 창 닫기

      // 4. 지오펜싱(Geofencing) 로직: 8km 이내인지 확인
      if (distanceInMeters <= MAX_DISTANCE_METERS) {
        // 8km 이내면 참가 성공 -> 채팅방이나 상세 페이지로 이동
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('참가 성공! ${(distanceInMeters / 1000).toStringAsFixed(1)}km 거리에 있습니다.')),
        );
        // TODO: Navigator.push(context, MaterialPageRoute(builder: (context) => ChatRoomScreen(...)));
      } else {
        // 8km 초과면 참가 거부 알림
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: Text('📍 참여 불가'),
            content: Text('현재 위치에서 모임 장소까지의 거리가 ${(distanceInMeters / 1000).toStringAsFixed(1)}km 입니다.\n동네 번개 모임은 8km 이내에서만 참여할 수 있습니다.'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text('확인'),
              ),
            ],
          ),
        );
      }
    } catch (e) {
      Navigator.pop(context); // 로딩 창 닫기
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('위치 정보를 가져오는데 실패했습니다.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('🌐 동네 번개 둘러보기'),
      ),
      // Firestore에서 모든 모임 데이터를 실시간으로 가져옴 (생성일 최신순)
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('meetups')
            .orderBy('createdAt', descending: true)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return Center(child: CircularProgressIndicator());
          }
          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
            return Center(child: Text('현재 활성화된 모임이 없습니다.'));
          }

          final meetups = snapshot.data!.docs;

          return ListView.builder(
            itemCount: meetups.length,
            itemBuilder: (context, index) {
              var meetup = meetups[index];
              
              // Firestore 문서 필드값들 (DB 구조에 맞게 수정 필요)
              String title = meetup['title'] ?? '제목 없음';
              String category = meetup['category'] ?? '기타';
              int currentMembers = meetup['currentMembers'] ?? 1;
              int maxMembers = meetup['maxMembers'] ?? 4;

              return Card(
                margin: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: ListTile(
                  leading: CircleAvatar(
                    child: Icon(Icons.people),
                  ),
                  title: Text(title, style: TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: Text('카테고리: $category | 인원: $currentMembers/$maxMembers명'),
                  trailing: ElevatedButton(
                    onPressed: () {
                      // 참가 버튼 누를 때 거리 계산 로직 실행
                      _checkDistanceAndJoin(context, meetup);
                    },
                    child: Text('참가 확인'),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}