import 'dart:convert';

import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart' as http;

/// 동네 이름(예: "역삼동", "서초구 반포동")을 입력하면 Google Geocoding API로
/// 해당 위치의 좌표를 찾아주는 서비스입니다.
///
/// ⚠️ 사용 전 Google Cloud Console에서 이 프로젝트의 Maps API 키에
/// "Geocoding API"가 활성화되어 있어야 합니다. (기존에는 지도 표시용
/// API만 켜져 있을 가능성이 높습니다 - 프로젝트 관리자가 켜줘야 함)
class GeocodingService {
  // web/index.html에서 지도 표시에 쓰는 것과 같은 프로젝트의 API 키입니다.
  static const String _apiKey = 'AIzaSyAvrClijLdj-qBmnFd2t4x8ubARtpBZHWE';

  /// 검색어로 위치를 찾아 좌표를 반환합니다. 못 찾으면 null을 반환합니다.
  /// API 자체 오류(키 미설정 등)인 경우 [GeocodingException]을 던집니다.
  static Future<LatLng?> searchPlace(String query) async {
    final uri = Uri.https('maps.googleapis.com', '/maps/api/geocode/json', {
      'address': query,
      'language': 'ko',
      'region': 'kr',
      'components': 'country:KR',
      'key': _apiKey,
    });

    final response = await http.get(uri).timeout(const Duration(seconds: 10));

    if (response.statusCode != 200) {
      throw GeocodingException('위치 검색 서버에 연결하지 못했습니다. (${response.statusCode})');
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final status = data['status'] as String?;

    if (status == 'ZERO_RESULTS') {
      return null;
    }

    if (status != 'OK') {
      final errorMessage = data['error_message'] as String?;
      throw GeocodingException(
        errorMessage ?? '위치 검색에 실패했습니다. (상태: $status) — Geocoding API가 활성화되어 있는지 확인해주세요.',
      );
    }

    final results = data['results'] as List<dynamic>;
    if (results.isEmpty) return null;

    final location = results.first['geometry']['location'] as Map<String, dynamic>;
    return LatLng(
      (location['lat'] as num).toDouble(),
      (location['lng'] as num).toDouble(),
    );
  }
}

class GeocodingException implements Exception {
  final String message;
  GeocodingException(this.message);

  @override
  String toString() => message;
}
