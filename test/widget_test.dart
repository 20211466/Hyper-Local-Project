import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// 🚀 프로젝트 이름(hyper_local_project)이 본인 것과 같은지 확인하세요!
import 'package:hyper_local_project/views/map_screen.dart';

void main() {
  testWidgets('MapScreen 로딩 테스트', (WidgetTester tester) async {
    // 앱 빌드
    await tester.pumpWidget(const MaterialApp(home: MapScreen()));

    // 화면에 'Hyper-Local'이라는 문구가 있는지 확인
    expect(find.textContaining('Hyper-Local'), findsOneWidget);
  });
}