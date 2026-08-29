import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_blue_classic/flutter_blue_classic.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart' as latLng;

import 'dashboard_screen.dart';
import 'notifications.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await [
    Permission.bluetooth,
    Permission.bluetoothScan,
    Permission.bluetoothConnect,
    Permission.location,
    Permission.notification,
  ].request();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      debugShowCheckedModeBanner: false,
      home: HomeScreen(),
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final FlutterBlueClassic _bt = FlutterBlueClassic();
  final String targetName = "ESP32_Motion_Alert";

  BluetoothConnection? _connection;
  bool _connected = false;

  // LIVE VALUES
  double speed = 0.0;
  double distance = 0.0;
  double calories = 0.0;
  double? _lat;
  double? _lng;

  String _status = "Not Connected";
  StreamSubscription<Uint8List>? _inputSub;
  final List<String> _logs = [];
  final Notifications notifications = Notifications();

  String _rxBuffer = '';

  @override
  void initState() {
    super.initState();
    notifications.initNotifications();
  }

  @override
  void dispose() {
    _inputSub?.cancel();
    _connection?.dispose();
    super.dispose();
  }

  // CONNECT BUTTON
  Future<void> _connectPressed() async {
    setState(() => _status = "Searching paired...");
    final paired = await _bt.bondedDevices;

    if (paired == null || paired.isEmpty) {
      setState(() => _status = "No paired devices found");
      return;
    }

    for (var dev in paired) {
      if (dev.name == targetName) {
        await _connectTo(dev.address);
        return;
      }
    }
    setState(() => _status = "Device not found");
  }

  Future<void> _connectTo(String address) async {
    setState(() => _status = "Connecting...");
    final conn = await _bt.connect(address);

    if (conn == null) {
      setState(() => _status = "Failed to connect");
      return;
    }

    _connection = conn;
    _connected = true;
    setState(() => _status = "Connected");

    // Robust line-buffer input listener
    _inputSub = conn.input?.listen((Uint8List data) {
      final chunk = utf8.decode(data, allowMalformed: true);
      _rxBuffer += chunk;

      final lines = _rxBuffer.split(RegExp(r'[\r\n]+'));
      if (!_rxBuffer.endsWith('\n') && !_rxBuffer.endsWith('\r')) {
        _rxBuffer = lines.removeLast();
      } else {
        _rxBuffer = '';
      }

      for (final rawLine in lines) {
        final text = rawLine.trim();
        if (text.isEmpty) continue;

        setState(() => _logs.insert(0, "RX: $text"));

        // GPS
        if (text.startsWith("GPS,")) {
          final p = text.split(',');
          if (p.length >= 3) {
            _lat = double.tryParse(p[1]);
            _lng = double.tryParse(p[2]);
            setState(() {});
          }
        }

        // HALL
        if (text.startsWith("HALL,")) {
          final p = text.split(',');
          if (p.length >= 6) {
            speed = double.tryParse(p[1]) ?? 0.0;
            distance = double.tryParse(p[3]) ?? 0.0;
            calories = double.tryParse(p[5]) ?? 0.0;
            setState(() {});
          }
        }

        // ACK
        if (text.startsWith("ACK,")) {
          setState(() => _logs.insert(0, "ACK: ${text.substring(4)}"));
        }

        // ALERT
        if (text.startsWith("ALERT,")) {
          if (text.contains("MOTION_DETECTED")) {
            notifications.showNotification(
              "Motion Detected!",
              "Your bike is being moved!",
            );
          }
        }
      }
    }, onDone: () {
      _connected = false;
      setState(() => _status = "Disconnected");
    }, onError: (e) {
      _connected = false;
      setState(() => _status = "Error: $e");
    });
  }

  void _sendCommand(String cmd) {
    if (_connected && _connection != null) {
      _connection!.writeString("$cmd\n");
    }
  }

  @override
  Widget build(BuildContext context) {
    final marker = (_lat != null && _lng != null)
        ? Marker(
            point: latLng.LatLng(_lat!, _lng!),
            width: 40,
            height: 40,
            child: const Icon(Icons.location_pin, size: 40, color: Colors.red),
          )
        : null;

    return Scaffold(
      appBar: AppBar(
        title: const Text("Smart Bike Tracker"),
        backgroundColor: Colors.teal,
      ),
      body: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            ElevatedButton.icon(
              icon: const Icon(Icons.bluetooth),
              label: const Text("Connect to Bike"),
              onPressed: _connected ? null : _connectPressed,
            ),
            const SizedBox(height: 10),
            Card(
              child: ListTile(
                leading: Icon(
                  _connected ? Icons.bluetooth_connected : Icons.bluetooth_disabled,
                  color: _connected ? Colors.green : Colors.red,
                ),
                title: Text(_status),
              ),
            ),
            const SizedBox(height: 12),
            if (_lat != null && _lng != null)
              SizedBox(
                height: 250,
                child: FlutterMap(
                  options: MapOptions(
                    initialCenter: latLng.LatLng(_lat!, _lng!),
                    initialZoom: 16,
                  ),
                  children: [
                    TileLayer(
                      urlTemplate: "https://tile.openstreetmap.org/{z}/{x}/{y}.png",
                      userAgentPackageName: "com.bike.app",
                    ),
                    if (marker != null) MarkerLayer(markers: [marker]),
                  ],
                ),
              )
            else
              const Text("Waiting for GPS..."),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              icon: const Icon(Icons.speed),
              label: const Text("Open Dashboard"),
              onPressed: _connected
                  ? () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => DashboardScreen(
                            speedRef: () => speed,
                            distanceRef: () => distance,
                            caloriesRef: () => calories,
                            onReset: () {
                              setState(() {
                                distance = 0;
                                calories = 0;
                              });
                              _sendCommand("RESET_STATS");
                            },
                            sendCommand: _sendCommand,
                          ),
                        ),
                      );
                    }
                  : null,
            ),
            const Divider(),
            const Text("Logs", style: TextStyle(fontWeight: FontWeight.bold)),
            Expanded(
              child: ListView.builder(
                itemCount: _logs.length,
                itemBuilder: (_, i) => Card(
                  child: ListTile(title: Text(_logs[i])),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
