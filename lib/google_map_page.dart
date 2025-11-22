import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';

class MapPage extends StatefulWidget {
  // --- UPDATE LIST EVENT MARKERS  ---
  final List<Map<String, dynamic>> events;

  const MapPage({super.key, required this.events});
  // -------------------------------------------------------------

  @override
  State<MapPage> createState() => _MapPageState();
}

class _MapPageState extends State<MapPage> {
  GoogleMapController? _controller;
  Position? _pos;
  final Set<Marker> _markers = {};

  @override
  void initState() {
    super.initState();
    _initLocation();
  }

  Future<void> _initLocation() async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) return;

    var perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) {
      perm = await Geolocator.requestPermission();
      if (perm == LocationPermission.deniedForever ||
          perm == LocationPermission.denied) {
        return;
      }
    }

    try {
      final p = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.medium,
      );
      setState(() {
        _pos = p;
      });
      _updateMarkers();
      _moveCamera();
    } catch (e) {
      debugPrint("Gagal mengambil lokasi: $e");
    }
  }

  void _updateMarkers() {
    setState(() {
      _markers.clear();

      // 1. Marker Posisi Saya
      if (_pos != null) {
        _markers.add(
          Marker(
            markerId: const MarkerId('me'),
            position: LatLng(_pos!.latitude, _pos!.longitude),
            infoWindow: const InfoWindow(title: 'Posisi Saya'),
          ),
        );
      }

      // 2. Marker Event Kampus (Looping dari data events)
      for (var event in widget.events) {
        _markers.add(
          Marker(
            markerId: MarkerId(event['title']),
            position: LatLng(event['lat'], event['lng']),
            infoWindow: InfoWindow(
              title: event['title'],
              snippet: 'Event Kampus',
            ),
            icon: BitmapDescriptor.defaultMarkerWithHue(
              BitmapDescriptor.hueAzure,
            ),
          ),
        );
      }
    });
  }

  void _moveCamera() {
    if (_controller == null || _pos == null) return;
    _controller!.animateCamera(
      CameraUpdate.newLatLngZoom(LatLng(_pos!.latitude, _pos!.longitude), 15),
    );
  }

  @override
  Widget build(BuildContext context) {
    final center = _pos != null
        ? LatLng(_pos!.latitude, _pos!.longitude)
        : const LatLng(-7.4246, 109.2332);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Peta Event (Google Maps)'),
        backgroundColor: Colors.indigo.withOpacity(0.8),
      ),
      body: GoogleMap(
        initialCameraPosition: CameraPosition(target: center, zoom: 14),
        myLocationEnabled: true,
        myLocationButtonEnabled: true,
        markers: _markers,
        onMapCreated: (c) {
          _controller = c;
          _moveCamera();
        },
      ),
    );
  }
}