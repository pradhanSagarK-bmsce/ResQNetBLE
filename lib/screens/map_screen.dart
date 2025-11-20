import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../services/ble_service.dart';

class MapScreen extends StatelessWidget {
  const MapScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final ble = Provider.of<BleService>(context);
    final markers = ble.devices.entries
        .map((e) {
          final s = e.value;
          if (!s.gpsValid) return null;
          return Marker(
            point: LatLng(s.lat, s.lon),
            width: 80,
            height: 80,
            child: GestureDetector(
              onTap: () => Navigator.pushNamed(
                context,
                '/detail',
                arguments: {'id': e.key},
              ),
              child: Column(
                children: [
                  Icon(
                    Icons.location_on,
                    color: s.urgent ? Colors.red : Colors.green,
                    size: 36,
                  ),
                  Text(e.key, style: const TextStyle(fontSize: 10)),
                ],
              ),
            ),
          );
        })
        .where((m) => m != null)
        .cast<Marker>()
        .toList();

    return Scaffold(
      appBar: AppBar(title: const Text('Rescue Map')),
      body: FlutterMap(
        options: MapOptions(
          initialCenter: LatLng(20.0, 78.0),
          initialZoom: 5.0,
        ),
        children: [
          TileLayer(
            urlTemplate: 'https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png',
            subdomains: ['a', 'b', 'c'],
          ),
          MarkerLayer(markers: markers),
        ],
      ),
    );
  }
}
