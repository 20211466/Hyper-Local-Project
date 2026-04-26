import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

class MapScreen extends StatefulWidget {
  const MapScreen({super.key});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  // 처음 지도가 보여줄 위치 (예: 서울 중심)
  static const CameraPosition _initialPosition = CameraPosition(
    target: LatLng(37.5665, 126.9780),
    zoom: 14.4746,
  );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Hyper-Local 지도')),
      body: const GoogleMap(
        initialCameraPosition: _initialPosition,
        myLocationEnabled: true, // 내 위치 버튼 활성화
        myLocationButtonEnabled: true,
      ),
    );
  }
}