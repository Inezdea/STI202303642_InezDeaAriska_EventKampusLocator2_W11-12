import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart' as gc;

// Import halaman peta
import 'google_map_page.dart';
import 'osm_map_page.dart';

void main() => runApp(const MyApp());

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Event Kampus Locator',
      theme: ThemeData(
        colorSchemeSeed: Colors.indigo,
        useMaterial3: true,
        brightness: Brightness.dark,
      ),
      home: const HomePage(),
      debugShowCheckedModeBanner: false,
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  Position? _pos;
  String? _address;
  StreamSubscription<Position>? _sub;

  bool _tracking = false;
  String _status = 'Lokasi belum terlacak.';

  // Default ke LOW (Hemat Baterai)
  LocationAccuracy _selectedAccuracy = LocationAccuracy.low;

  final List<Map<String, dynamic>> _events = const [
    {'title': 'Seminar AI', 'lat': -7.4246, 'lng': 109.2332},
    {'title': 'Job Fair', 'lat': -7.4261, 'lng': 109.2315},
    {'title': 'Expo UKM', 'lat': -7.4229, 'lng': 109.2350},
    {'title': 'Workshop Flutter', 'lat': -7.4300, 'lng': 109.2340},
    {'title': 'Lomba E-Sport', 'lat': -7.4210, 'lng': 109.2290},
  ];

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  Future<bool> _ensureServiceAndPermission() async {
    // Cek apakah GPS / lokasi hidup
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      final activated = await _showGpsOffDialog();

      if (!activated) {
        setState(() => _status = 'Layanan lokasi MATI.');
        return false; // GPS tetap mati
      }
    }

    // Cek izin aplikasi
    LocationPermission perm = await Geolocator.checkPermission();

    if (perm == LocationPermission.denied) {
      perm = await Geolocator.requestPermission();
    }

    if (perm == LocationPermission.deniedForever ||
        perm == LocationPermission.denied) {
      await _showWarningDialog(
        "Izin Lokasi Ditolak",
        "Aplikasi membutuhkan akses lokasi untuk melacak event terdekat.\n\n"
            "Silakan buka Pengaturan → Izin Aplikasi → Aktifkan Lokasi.",
      );

      setState(() => _status = 'Izin lokasi ditolak.');
      return false;
    }

    return true;
  }

  Future<void> _getCurrent() async {
    if (!await _ensureServiceAndPermission()) return;
    setState(() => _status = "Mengambil lokasi...");

    try {
      final p = await Geolocator.getCurrentPosition(
        desiredAccuracy: _selectedAccuracy,
        timeLimit: const Duration(seconds: 10),
      );
      setState(() {
        _pos = p;
        _status = 'Lokasi Terkini Didapat.';
      });
      _reverseGeocode(p);
    } catch (e) {
      setState(() => _status = 'Gagal: $e');
    }
  }

  Future<void> _reverseGeocode(Position p) async {
    try {
      final placemarks = await gc.placemarkFromCoordinates(
        p.latitude,
        p.longitude,
      );
      if (placemarks.isNotEmpty) {
        final m = placemarks.first;
        setState(() {
          _address = '${m.street}, ${m.locality}';
        });
      }
    } catch (e) {
      debugPrint("Error reverseGeocode: $e");
    }
  }

  //Alert Dialog Gps

  Future<void> _showWarningDialog(String title, String message) async {
    return showDialog(
      context: context,
      barrierDismissible: true,
      builder: (_) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("OK"),
          ),
        ],
      ),
    );
  }

  // Logika: Jika High Accuracy -> Pakai Background Service.
  Future<void> _toggleTracking() async {
    if (_tracking) {
      await _sub?.cancel();
      _sub = null;
      setState(() {
        _tracking = false;
        _status = 'Tracking Berhenti.';
      });
      return;
    }

    if (!await _ensureServiceAndPermission()) return;

    setState(() => _status = "Menyiapkan Tracking...");

    late LocationSettings settings;

    //  Cek Akurasi Tinggi DAN Android
    if (_selectedAccuracy == LocationAccuracy.high && Platform.isAndroid) {
      settings = AndroidSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 10,
        intervalDuration: const Duration(seconds: 5),
        // Notifikasi hanya muncul jika High Accuracy
        foregroundNotificationConfig: const ForegroundNotificationConfig(
          notificationTitle: "Mode GPS Aktif",
          notificationText: "Melacak lokasi event di background...",
          notificationIcon: AndroidResource(name: 'ic_launcher'),
          enableWakeLock: true,
        ),
      );
    } else {
      // Mode Hemat / Biasa (Tanpa Notifikasi Background)
      settings = const LocationSettings(
        accuracy: LocationAccuracy.low,
        distanceFilter: 10,
      );
    }

    try {
      _sub = Geolocator.getPositionStream(locationSettings: settings).listen(
            (p) {
          setState(() {
            _pos = p;
            _tracking = true;
            _status =
            'Update: ${DateTime.now().hour}:${DateTime.now().minute}:${DateTime.now().second}';
          });
          _reverseGeocode(p);
        },
        onError: (e) {
          setState(() {
            _tracking = false;
            _status = 'Error Stream: $e';
          });
        },
      );
    } catch (e) {
      setState(() => _status = "Gagal memulai stream: $e");
    }
  }

  double _distanceM(Position me, Map e) => Geolocator.distanceBetween(
    me.latitude,
    me.longitude,
    e['lat'] as double,
    e['lng'] as double,
  );

  Widget _buildEventList(Position me) {
    final eventListWithDistance = _events.map((e) {
      final double d = _distanceM(me, e);
      return {...e, 'distance': d};
    }).toList();

    eventListWithDistance.sort(
          (a, b) => (a['distance'] as double).compareTo(b['distance'] as double),
    );

    return ListView.separated(
      padding: const EdgeInsets.only(top: 0, bottom: 80),
      itemCount: eventListWithDistance.length,
      separatorBuilder: (context, index) =>
      const Divider(color: Colors.white10, height: 1),
      itemBuilder: (context, index) {
        final e = eventListWithDistance[index];
        final d = e['distance'] as double;
        return ListTile(
          dense: true,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 0,
          ),
          leading: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.blueAccent.withOpacity(0.2),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.event_available,
              color: Colors.blueAccent,
              size: 20,
            ),
          ),
          title: Text(
            e['title'] as String,
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          subtitle: Text(
            '${d.toStringAsFixed(0)} meter',
            style: const TextStyle(color: Colors.grey),
          ),
          trailing: const Icon(
            Icons.arrow_forward_ios,
            size: 12,
            color: Colors.grey,
          ),
        );
      },
    );
  }

  void _showHighAccuracyDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        icon: const Icon(
          Icons.battery_alert_rounded,
          color: Color.fromARGB(223, 255, 0, 0),
          size: 40,
        ),
        title: const Text("Aktifkan Mode GPS?"),
        content: const Text("Baterai akan lebih cepat habis."),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Batal"),
          ),
          FilledButton(
            onPressed: () {
              setState(() => _selectedAccuracy = LocationAccuracy.high);
              Navigator.pop(context);
            },
            child: const Text("Ya"),
          ),
        ],
      ),
    );
  }

  Future<bool> _showGpsOffDialog() async {
    final completer = Completer<bool>();

    // Listener perubahan status GPS
    late StreamSubscription<ServiceStatus> gpsListener;
    gpsListener = Geolocator.getServiceStatusStream().listen((status) {
      if (status == ServiceStatus.enabled) {
        gpsListener.cancel();
        if (!completer.isCompleted) {
          completer.complete(true); // GPS aktif otomatis
        }
        Navigator.of(context, rootNavigator: true).pop(); // Tutup dialog
      }
    });

    // Tampilkan dialog
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: Row(
            children: [
              Icon(
                Icons.location_on_rounded,
                color: const Color(0xFFFF5252),
                size: 32,
              ),
              const SizedBox(width: 10),
              const Text("Aktifkan GPS"),
            ],
          ),
          content: const Text(
            "GPS belum aktif. Silakan hidupkan layanan lokasi terlebih dahulu.",
            style: TextStyle(fontSize: 14),
          ),
          actions: [
            // Tombol 1: Buka Pengaturan
            TextButton(
              onPressed: () {
                Geolocator.openLocationSettings();
              },
              // Opsional: Jika ingin memastikan warna teks biru muda
              style: TextButton.styleFrom(
                foregroundColor: Colors.lightBlueAccent,
              ),
              child: const Text("Buka Pengaturan"),
            ),

            // Tombol 2: Batal
            TextButton(
              onPressed: () {
                gpsListener.cancel();
                if (!completer.isCompleted) {
                  completer.complete(false);
                }
                Navigator.pop(context);
              },
              // Opsional: Warna teks sama
              style: TextButton.styleFrom(
                foregroundColor: Colors.lightBlueAccent,
              ),
              child: const Text("Batal"),
            ),
          ],
        );
      },
    );

    return completer.future;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Event Kampus Locator'),
        elevation: 0,
        actions: [
          if (_tracking)
            Padding(
              padding: const EdgeInsets.only(right: 16.0),
              child: const Icon(
                Icons.location_on,
                color: Color.fromARGB(255, 222, 58, 58),
                size: 28,
              ),
            ),
        ],
      ),
      body: Column(
        children: [
          // List Event
          Material(
            color: Colors.grey[900],
            elevation: 2,
            borderRadius: const BorderRadius.vertical(
              bottom: Radius.circular(16),
            ),
            child: Column(
              children: [
                // Baris 1: Status & Toggle
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 4,
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              "Status:",
                              style: TextStyle(
                                fontSize: 10,
                                color: Color.fromARGB(255, 69, 214, 134),
                              ),
                            ),
                            Text(
                              _status,
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Row(
                        children: [
                          Text(
                            _selectedAccuracy == LocationAccuracy.high
                                ? "GPS"
                                : "WiFi/Cell",
                            style: TextStyle(
                              fontSize: 10,
                              color: _selectedAccuracy == LocationAccuracy.high
                                  ? Colors.green
                                  : Colors.green,
                            ),
                          ),
                          Transform.scale(
                            scale: 0.7,
                            child: Switch(
                              value: _selectedAccuracy == LocationAccuracy.high,
                              activeColor: Colors.greenAccent,
                              onChanged: _tracking
                                  ? null
                                  : (val) {
                                if (val)
                                  _showHighAccuracyDialog();
                                else
                                  setState(
                                        () => _selectedAccuracy =
                                        LocationAccuracy.low,
                                  );
                              },
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                // Baris 2: Expansion Tile (Detail Lokasi)
                Theme(
                  data: Theme.of(
                    context,
                  ).copyWith(dividerColor: Colors.transparent),
                  child: ExpansionTile(
                    title: Text(
                      _pos == null
                          ? "Tampilkan Data Detail"
                          : "Lat: ${_pos!.latitude.toStringAsFixed(4)}, Lng: ${_pos!.longitude.toStringAsFixed(4)}",
                      style: const TextStyle(
                        fontSize: 12,
                        color: Colors.blueAccent,
                      ),
                    ),
                    iconColor: Colors.blueAccent,
                    collapsedIconColor: Colors.blueAccent,
                    childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    children: [
                      if (_pos != null) ...[
                        const Divider(color: Colors.white12),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            _infoItem(
                              "Akurasi",
                              "${_pos!.accuracy.toStringAsFixed(1)} m",
                            ),
                            _infoItem(
                              "Speed",
                              "${(_pos!.speed * 3.6).toStringAsFixed(1)} km/h",
                            ),
                            _infoItem(
                              "Heading",
                              "${_pos!.heading.toStringAsFixed(0)}°",
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        _infoItem(
                          "Waktu",
                          _pos!.timestamp.toString().split('.')[0],
                        ),
                        if (_address != null) ...[
                          const SizedBox(height: 8),
                          _infoItem("Alamat", _address!),
                        ],
                      ] else
                        const Padding(
                          padding: EdgeInsets.all(8.0),
                          child: Text(
                            "Belum ada data lokasi.",
                            style: TextStyle(color: Colors.grey, fontSize: 12),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // List Event
          if (_pos != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Row(
                children: [
                  const Icon(Icons.sort, size: 16, color: Colors.grey),
                  const SizedBox(width: 8),
                  Text(
                    "Event Terdekat (${_events.length})",
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.grey,
                    ),
                  ),
                ],
              ),
            ),

          Expanded(
            child: _pos != null
                ? _buildEventList(_pos!)
                : const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.map_outlined, size: 48, color: Colors.grey),
                  SizedBox(height: 8),
                  Text(
                    "Ambil lokasi untuk melihat event",
                    style: TextStyle(color: Colors.grey),
                  ),
                ],
              ),
            ),
          ),

          // Baris Tombol Aksi
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Theme.of(context).scaffoldBackgroundColor,
              border: const Border(top: BorderSide(color: Colors.white10)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                // Tombol Get Current (Bulat Kecil)
                FloatingActionButton.small(
                  heroTag: "btn1",
                  onPressed: _getCurrent,
                  tooltip: "Get Current",
                  backgroundColor: Colors.indigoAccent,
                  child: const Icon(Icons.my_location, color: Colors.white),
                ),
                // Tombol Tracking (Bulat Kecil)
                FloatingActionButton.small(
                  heroTag: "btn2",
                  onPressed: _toggleTracking,
                  tooltip: "Toggle Tracking",
                  backgroundColor: _tracking ? Colors.redAccent : Colors.teal,
                  child: Icon(
                    _tracking ? Icons.stop : Icons.play_arrow,
                    color: Colors.white,
                  ),
                ),
                // Tombol Maps (Chip)
                ActionChip(
                  avatar: const Icon(Icons.map, size: 16),
                  label: const Text("G-Maps"),
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => MapPage(events: _events)),
                  ),
                ),
                // Tombol OSM (Chip)
                ActionChip(
                  avatar: const Icon(Icons.map_outlined, size: 16),
                  label: const Text("OSM"),
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => OsmMapPage(events: _events),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // Helper widget untuk info kecil
  Widget _infoItem(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 10, color: Colors.grey)),
        Text(
          value,
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
        ),
      ],
    );
  }
}