import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/route_service.dart';

class RouteGuideScreen extends StatefulWidget {
  final LatLng destination;
  final String destinationName;
  final RouteTravelMode mode;

  const RouteGuideScreen({
    super.key,
    required this.destination,
    required this.destinationName,
    required this.mode,
  });

  @override
  State<RouteGuideScreen> createState() => _RouteGuideScreenState();
}

class _RouteGuideScreenState extends State<RouteGuideScreen> {
  GoogleMapController? _mapController;
  StreamSubscription<Position>? _positionSubscription;

  LatLng? _currentPosition;
  double _currentHeading = 0;
  RouteResult? _route;
  List<double> _remainingFromPoint = <double>[];

  bool _isLoading = true;
  bool _isRerouting = false;
  String? _errorMessage;
  String? _routeStatusMessage;
  double _remainingDistanceMeters = 0;
  double _distanceFromRouteMeters = 0;
  DateTime? _lastRerouteAt;
  bool _initialCameraFitted = false;

  bool get _isWalking => widget.mode == RouteTravelMode.walking;
  String get _modeLabel => _isWalking ? '도보' : '자전거';
  IconData get _modeIcon => _isWalking ? Icons.directions_walk : Icons.directions_bike;

  @override
  void initState() {
    super.initState();
    _initializeGuide();
  }

  @override
  void dispose() {
    _positionSubscription?.cancel();
    super.dispose();
  }

  Future<void> _initializeGuide() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        throw const _GuideException('휴대전화의 위치 서비스를 켜 주세요.');
      }

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }

      if (permission == LocationPermission.denied) {
        throw const _GuideException('길안내를 위해 위치 권한이 필요합니다.');
      }
      if (permission == LocationPermission.deniedForever) {
        throw const _GuideException('위치 권한이 영구적으로 거부되었습니다. 앱 설정에서 위치 권한을 허용해 주세요.');
      }

      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
      final start = LatLng(position.latitude, position.longitude);

      if (!mounted) return;
      setState(() {
        _currentPosition = start;
        _currentHeading = position.heading;
      });

      await _loadRoute(start, initial: true);
      if (!mounted) return;

      _positionSubscription?.cancel();
      _positionSubscription = Geolocator.getPositionStream(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: 5,
        ),
      ).listen(
        _onPositionChanged,
        onError: (Object error) {
          if (mounted) {
            setState(() {
              _routeStatusMessage = '현재 위치를 실시간으로 갱신하지 못하고 있습니다.';
            });
          }
        },
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMessage = e is _GuideException ? e.message : e.toString();
      });
    }
  }

  Future<void> _loadRoute(LatLng origin, {bool initial = false}) async {
    if (initial && mounted) {
      setState(() {
        _isLoading = true;
        _errorMessage = null;
      });
    }

    try {
      final result = await RouteService.fetchRoute(
        origin: origin,
        destination: widget.destination,
        mode: widget.mode,
      );

      if (!mounted) return;
      setState(() {
        _route = result;
        _remainingDistanceMeters = result.distanceMeters;
        _remainingFromPoint = _buildRemainingDistances(result.points);
        _isLoading = false;
        _errorMessage = null;
        _routeStatusMessage = null;
      });

      if (initial) {
        await _fitRouteOnMap();
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        if (initial || _route == null) {
          _errorMessage = e.toString();
        } else {
          _routeStatusMessage = '경로 재탐색에 실패했습니다. 기존 경로를 계속 표시합니다.';
        }
      });
    }
  }

  List<double> _buildRemainingDistances(List<LatLng> points) {
    final remaining = List<double>.filled(points.length, 0);
    for (var i = points.length - 2; i >= 0; i--) {
      remaining[i] = Geolocator.distanceBetween(
            points[i].latitude,
            points[i].longitude,
            points[i + 1].latitude,
            points[i + 1].longitude,
          ) +
          remaining[i + 1];
    }
    return remaining;
  }

  void _onPositionChanged(Position position) {
    if (!mounted) return;
    final current = LatLng(position.latitude, position.longitude);
    final route = _route;

    setState(() {
      _currentPosition = current;
      _currentHeading = position.heading;
    });

    if (route == null || route.points.length < 2) return;

    final progress = _measureProgress(current, route.points);
    setState(() {
      _remainingDistanceMeters = progress.remainingMeters;
      _distanceFromRouteMeters = progress.distanceToRouteMeters;
    });

    // 현재 위치가 경로에서 90m 이상 벗어난 경우에만 재탐색합니다.
    // 공개 서버 과다 호출을 피하기 위해 재탐색 간격을 최소 20초로 제한합니다.
    if (progress.distanceToRouteMeters > 90) {
      _tryReroute(current);
    }
  }

  _RouteProgress _measureProgress(LatLng current, List<LatLng> points) {
    var nearestDistance = double.infinity;
    var remainingDistance = _route?.distanceMeters ?? 0;

    final cosLatitude = math.cos(current.latitude * math.pi / 180);

    for (var i = 0; i < points.length - 1; i++) {
      final a = points[i];
      final b = points[i + 1];

      // 현재 위치를 원점으로 한 평면 좌표에서 선분에 가장 가까운 점을 계산합니다.
      final ax = (a.longitude - current.longitude) * cosLatitude;
      final ay = a.latitude - current.latitude;
      final bx = (b.longitude - current.longitude) * cosLatitude;
      final by = b.latitude - current.latitude;
      final dx = bx - ax;
      final dy = by - ay;
      final denominator = dx * dx + dy * dy;

      var t = 0.0;
      if (denominator > 0) {
        t = (-(ax * dx + ay * dy) / denominator).clamp(0.0, 1.0).toDouble();
      }

      final projected = LatLng(
        a.latitude + (b.latitude - a.latitude) * t,
        a.longitude + (b.longitude - a.longitude) * t,
      );

      final distanceToSegment = Geolocator.distanceBetween(
        current.latitude,
        current.longitude,
        projected.latitude,
        projected.longitude,
      );

      if (distanceToSegment < nearestDistance) {
        nearestDistance = distanceToSegment;
        final distanceToNextPoint = Geolocator.distanceBetween(
          projected.latitude,
          projected.longitude,
          b.latitude,
          b.longitude,
        );
        remainingDistance = distanceToNextPoint +
            (i + 1 < _remainingFromPoint.length
                ? _remainingFromPoint[i + 1]
                : 0);
      }
    }

    return _RouteProgress(
      remainingMeters: remainingDistance,
      distanceToRouteMeters: nearestDistance,
    );
  }

  Future<void> _tryReroute(LatLng current) async {
    if (_isRerouting) return;
    final now = DateTime.now();
    if (_lastRerouteAt != null &&
        now.difference(_lastRerouteAt!) < const Duration(seconds: 20)) {
      return;
    }

    _lastRerouteAt = now;
    setState(() {
      _isRerouting = true;
      _routeStatusMessage = '경로를 벗어나 새 경로를 찾고 있습니다.';
    });

    try {
      final result = await RouteService.fetchRoute(
        origin: current,
        destination: widget.destination,
        mode: widget.mode,
      );
      if (!mounted) return;
      setState(() {
        _route = result;
        _remainingFromPoint = _buildRemainingDistances(result.points);
        _remainingDistanceMeters = result.distanceMeters;
        _distanceFromRouteMeters = 0;
        _routeStatusMessage = '새 경로로 안내하고 있습니다.';
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _routeStatusMessage = '경로 재탐색에 실패했습니다. 기존 경로를 계속 표시합니다.';
        });
      }
    } finally {
      if (mounted) setState(() => _isRerouting = false);
    }
  }

  Future<void> _fitRouteOnMap() async {
    final controller = _mapController;
    final route = _route;
    if (controller == null || route == null || route.points.isEmpty || _initialCameraFitted) {
      return;
    }

    var minLat = route.points.first.latitude;
    var maxLat = route.points.first.latitude;
    var minLng = route.points.first.longitude;
    var maxLng = route.points.first.longitude;

    for (final point in route.points) {
      minLat = math.min(minLat, point.latitude).toDouble();
      maxLat = math.max(maxLat, point.latitude).toDouble();
      minLng = math.min(minLng, point.longitude).toDouble();
      maxLng = math.max(maxLng, point.longitude).toDouble();
    }

    if (minLat == maxLat && minLng == maxLng) return;

    _initialCameraFitted = true;
    try {
      await controller.animateCamera(
        CameraUpdate.newLatLngBounds(
          LatLngBounds(
            southwest: LatLng(minLat, minLng),
            northeast: LatLng(maxLat, maxLng),
          ),
          72,
        ),
      );
    } catch (_) {
      // 매우 짧은 경로 등으로 bounds 이동이 실패하면 현재 카메라를 유지합니다.
    }
  }

  Future<void> _centerOnCurrentLocation() async {
    final current = _currentPosition;
    if (current == null) return;
    await _mapController?.animateCamera(
      CameraUpdate.newCameraPosition(
        CameraPosition(
          target: current,
          zoom: 17,
          bearing: _currentHeading,
          tilt: 35,
        ),
      ),
    );
  }

  String _formatDistance(double meters) {
    if (!meters.isFinite || meters < 0) return '-';
    if (meters >= 1000) return '${(meters / 1000).toStringAsFixed(1)}km';
    return '${meters.round()}m';
  }

  String _formatRemainingTime() {
    final route = _route;
    if (route == null || route.distanceMeters <= 0) return '-';
    final ratio = (_remainingDistanceMeters / route.distanceMeters).clamp(0.0, 1.5);
    final minutes = (route.durationSeconds * ratio / 60).round();
    if (minutes < 1) return '1분 미만';
    return '약 $minutes분';
  }

  Set<Marker> get _markers => <Marker>{
        Marker(
          markerId: const MarkerId('route_destination'),
          position: widget.destination,
          infoWindow: InfoWindow(title: widget.destinationName),
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
        ),
      };

  Set<Polyline> get _polylines {
    final route = _route;
    if (route == null) return <Polyline>{};
    return <Polyline>{
      Polyline(
        polylineId: const PolylineId('in_app_route'),
        points: route.points,
        color: Colors.green.shade700,
        width: 7,
        geodesic: true,
        startCap: Cap.roundCap,
        endCap: Cap.roundCap,
      ),
    };
  }

  Future<void> _openOsmFixPage() async {
    final uri = Uri.parse('https://www.openstreetmap.org/fixthemap');
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    final initialTarget = _currentPosition ?? widget.destination;

    return Scaffold(
      appBar: AppBar(
        title: Text('앱 내 $_modeLabel 길안내'),
        backgroundColor: Colors.green,
        foregroundColor: Colors.white,
      ),
      body: Stack(
        children: [
          GoogleMap(
            initialCameraPosition: CameraPosition(target: initialTarget, zoom: 15),
            onMapCreated: (controller) {
              _mapController = controller;
              _fitRouteOnMap();
            },
            myLocationEnabled: true,
            myLocationButtonEnabled: false,
            compassEnabled: true,
            zoomControlsEnabled: false,
            mapToolbarEnabled: false,
            markers: _markers,
            polylines: _polylines,
          ),
          Positioned(
            top: 12,
            left: 16,
            right: 16,
            child: Card(
              elevation: 4,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                child: Row(
                  children: [
                    Icon(_modeIcon, color: Colors.green.shade700),
                    const SizedBox(width: 9),
                    Expanded(
                      child: Text(
                        '$_modeLabel 경로 · ${widget.destinationName}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                    if (_isRerouting)
                      const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            right: 16,
            bottom: 188,
            child: FloatingActionButton.small(
              heroTag: 'route_center_button',
              onPressed: _centerOnCurrentLocation,
              backgroundColor: Colors.white,
              foregroundColor: Colors.green.shade800,
              child: const Icon(Icons.my_location),
            ),
          ),
          if (_isLoading)
            Positioned.fill(
              child: Container(
                color: Colors.white.withOpacity(0.58),
                child: const Center(
                  child: Card(
                    child: Padding(
                      padding: EdgeInsets.all(20),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          CircularProgressIndicator(color: Colors.green),
                          SizedBox(height: 12),
                          Text('현재 위치와 경로를 확인하고 있습니다.'),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          if (_errorMessage != null && !_isLoading)
            Positioned.fill(
              child: Container(
                color: Colors.white.withOpacity(0.9),
                alignment: Alignment.center,
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.route, size: 48, color: Colors.orange),
                    const SizedBox(height: 14),
                    Text(_errorMessage!, textAlign: TextAlign.center),
                    const SizedBox(height: 16),
                    ElevatedButton.icon(
                      onPressed: _initializeGuide,
                      icon: const Icon(Icons.refresh),
                      label: const Text('다시 시도'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                        foregroundColor: Colors.white,
                      ),
                    ),
                    if (_errorMessage!.contains('권한'))
                      TextButton(
                        onPressed: () => Geolocator.openAppSettings(),
                        child: const Text('앱 위치 권한 설정'),
                      ),
                  ],
                ),
              ),
            ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: _buildRouteInfoPanel(),
          ),
        ],
      ),
    );
  }

  Widget _buildRouteInfoPanel() {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
        boxShadow: const <BoxShadow>[
          BoxShadow(color: Colors.black12, blurRadius: 12, offset: Offset(0, -3)),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Text('목적지까지 남은 거리', style: TextStyle(color: Colors.black54)),
                const Spacer(),
                Text(
                  _formatRemainingTime(),
                  style: const TextStyle(color: Colors.green, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 3),
            Text(
              _formatDistance(_remainingDistanceMeters),
              style: const TextStyle(fontSize: 30, fontWeight: FontWeight.bold),
            ),
            if (_routeStatusMessage != null) ...[
              const SizedBox(height: 5),
              Text(
                _routeStatusMessage!,
                style: TextStyle(
                  color: _isRerouting ? Colors.orange.shade800 : Colors.black54,
                  fontSize: 12,
                ),
              ),
            ],
            const SizedBox(height: 9),
            const Divider(height: 1),
            const SizedBox(height: 7),
            Row(
              children: [
                const Expanded(
                  child: Text(
                    '경로 데이터 © OpenStreetMap contributors · FOSSGIS',
                    style: TextStyle(fontSize: 10, color: Colors.black54),
                  ),
                ),
                TextButton(
                  onPressed: _openOsmFixPage,
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: const Text('지도 오류 수정', style: TextStyle(fontSize: 10)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _RouteProgress {
  final double remainingMeters;
  final double distanceToRouteMeters;

  const _RouteProgress({
    required this.remainingMeters,
    required this.distanceToRouteMeters,
  });
}

class _GuideException implements Exception {
  final String message;
  const _GuideException(this.message);
}
