import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';

class OsmMapPage extends StatefulWidget {
  final List<Map<String, dynamic>> events;

  const OsmMapPage({super.key, required this.events});

  @override
  State<OsmMapPage> createState() => _OsmMapPageState();
}

class _OsmMapPageState extends State<OsmMapPage> {
  Position? _pos;
  final mapController = MapController();

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
          perm == LocationPermission.denied)
        return;
    }

    try {
      final p = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.medium,
      );
      setState(() {
        _pos = p;
      });
      _moveCamera();
    } catch (e) {
      debugPrint("Gagal lokasi: $e");
    }
  }

  void _moveCamera() {
    if (_pos == null) return;
    mapController.move(LatLng(_pos!.latitude, _pos!.longitude), 15);
  }

  // Fungsi helper untuk menampilkan Info Event
  void _showEventInfo(String title, String snippet) {
    showModalBottomSheet(
      context: context,
      builder: (context) => Container(
        padding: const EdgeInsets.all(20),
        height: 150,
        width: double.infinity,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(snippet, style: const TextStyle(fontSize: 16)),
            const Spacer(),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text("Tutup"),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final center = _pos != null
        ? LatLng(_pos!.latitude, _pos!.longitude)
        : LatLng(-7.4246, 109.2332);

    List<Marker> allMarkers = [];

    // 1. Marker Saya (Dengan GestureDetector)
    if (_pos != null) {
      allMarkers.add(
        Marker(
          point: LatLng(_pos!.latitude, _pos!.longitude),
          width: 40,
          height: 40,
          child: GestureDetector(
            onTap: () => _showEventInfo(
              "Lokasi Anda",
              "Ini adalah posisi Anda saat ini.",
            ),
            child: const Icon(
              Icons.person_pin_circle,
              color: Colors.redAccent,
              size: 40,
            ),
          ),
        ),
      );
    }

    // 2. Marker Event (Dengan GestureDetector)
    for (var event in widget.events) {
      allMarkers.add(
        Marker(
          point: LatLng(event['lat'], event['lng']),
          width: 40,
          height: 40,
          // Bungkus Icon dengan GestureDetector agar bisa diklik
          child: GestureDetector(
            onTap: () {
              _showEventInfo(event['title'], "Event Kampus");
            },
            child: const Icon(Icons.location_on, color: Colors.blue, size: 40),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Peta Event (OSM)'),
        backgroundColor: Colors.indigo.withOpacity(0.8),
      ),
      body: FlutterMap(
        mapController: mapController,
        options: MapOptions(initialCenter: center, initialZoom: 14),
        children: [
          TileLayer(
            urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
            userAgentPackageName: 'com.example.event_kampus_locator',
          ),
          MarkerLayer(markers: allMarkers),
        ],
      ),
    );
  }
}