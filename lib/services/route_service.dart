import 'dart:convert';

import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart' as http;

/// 앱 내부 도보/자전거 길찾기 모드
///
/// 경로 계산은 FOSSGIS의 OpenStreetMap 기반 OSRM 공개 서버에서 수행하고,
/// 반환된 좌표는 앱의 GoogleMap 위에 직접 그립니다.
enum RouteTravelMode {
  walking,
  cycling,
}

class RouteResult {
  final List<LatLng> points;
  final double distanceMeters;
  final double durationSeconds;

  const RouteResult({
    required this.points,
    required this.distanceMeters,
    required this.durationSeconds,
  });
}

class RouteServiceException implements Exception {
  final String message;

  const RouteServiceException(this.message);

  @override
  String toString() => message;
}

class RouteService {
  RouteService._();

  static Future<RouteResult> fetchRoute({
    required LatLng origin,
    required LatLng destination,
    required RouteTravelMode mode,
  }) async {
    final profile = mode == RouteTravelMode.walking ? 'foot' : 'bike';

    // FOSSGIS는 교통수단별 서버(routed-foot / routed-bike)를 운영합니다.
    // 좌표 순서는 반드시 경도(longitude), 위도(latitude)입니다.
    final coordinates =
        '${origin.longitude},${origin.latitude};'
        '${destination.longitude},${destination.latitude}';

    final uri = Uri.parse(
      'https://routing.openstreetmap.de/routed-$profile/route/v1/driving/'
      '$coordinates?overview=full&geometries=geojson&steps=true',
    );

    late final http.Response response;
    try {
      response = await http
          .get(
            uri,
            headers: const <String, String>{
              'Accept': 'application/json',
              'User-Agent': 'HyperLocalMeetup/1.0 (graduation project)',
            },
          )
          .timeout(const Duration(seconds: 20));
    } catch (e) {
      throw const RouteServiceException(
        '경로 서버에 연결하지 못했습니다. 인터넷 연결을 확인한 뒤 다시 시도해 주세요.',
      );
    }

    if (response.statusCode != 200) {
      throw RouteServiceException(
        '경로 서버 응답 오류 (${response.statusCode})입니다. 잠시 후 다시 시도해 주세요.',
      );
    }

    late final Map<String, dynamic> body;
    try {
      body = jsonDecode(response.body) as Map<String, dynamic>;
    } catch (_) {
      throw const RouteServiceException('경로 응답을 읽을 수 없습니다.');
    }

    if (body['code'] != 'Ok') {
      throw const RouteServiceException(
        '이 위치 사이의 경로를 찾지 못했습니다. 출발지나 목적지 위치를 확인해 주세요.',
      );
    }

    final routes = body['routes'] as List<dynamic>?;
    if (routes == null || routes.isEmpty) {
      throw const RouteServiceException('이동 가능한 경로가 없습니다.');
    }

    final route = routes.first as Map<String, dynamic>;
    final geometry = route['geometry'] as Map<String, dynamic>?;
    final coordinatesList = geometry?['coordinates'] as List<dynamic>?;

    if (coordinatesList == null || coordinatesList.length < 2) {
      throw const RouteServiceException('경로 좌표가 충분하지 않습니다.');
    }

    final points = <LatLng>[];
    for (final coordinate in coordinatesList) {
      if (coordinate is List && coordinate.length >= 2) {
        final longitude = (coordinate[0] as num).toDouble();
        final latitude = (coordinate[1] as num).toDouble();
        points.add(LatLng(latitude, longitude));
      }
    }

    if (points.length < 2) {
      throw const RouteServiceException('지도에 표시할 경로 좌표가 없습니다.');
    }

    return RouteResult(
      points: points,
      distanceMeters: (route['distance'] as num).toDouble(),
      durationSeconds: (route['duration'] as num).toDouble(),
    );
  }
}
