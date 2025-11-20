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

    // Convert our 'nodes' map into Map Markers
    final markers = ble.nodes.values.map((node) {
      // Determine color based on status
      Color markerColor = Colors.green; // Normal
      if (node.isCritical) markerColor = Colors.redAccent;
      
      // Fade out if old
      final timeSince = DateTime.now().difference(node.lastSeen);
      if (timeSince.inSeconds > 30) markerColor = Colors.grey;

      return Marker(
        point: LatLng(node.lat, node.lon),
        width: 60,
        height: 60,
        child: GestureDetector(
          onTap: () {
            _showNodeDetails(context, node);
          },
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Stack(
                alignment: Alignment.center,
                children: [
                  Icon(
                    Icons.location_on,
                    color: markerColor,
                    size: 40,
                  ),
                  if (node.isCritical)
                    const Positioned(
                      top: 8,
                      child: Icon(
                        Icons.warning,
                        color: Colors.white,
                        size: 16,
                      ),
                    ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  "ID:${node.id}",
                  style: const TextStyle(
                    color: Colors.white, 
                    fontSize: 10, 
                    fontWeight: FontWeight.bold
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }).toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Rescue Mesh Map'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16.0),
            child: Center(
              child: Text(
                "${ble.nodes.length} Nodes", 
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          )
        ],
      ),
      body: FlutterMap(
        options: MapOptions(
          // Center on the simulation base location
          initialCenter: const LatLng(20.0, 78.0), 
          initialZoom: 12.0,
          interactionOptions: const InteractionOptions(
            flags: InteractiveFlag.all,
          ),
        ),
        children: [
          TileLayer(
            urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
            userAgentPackageName: 'com.example.mesh_app',
          ),
          MarkerLayer(markers: markers),
          
          // Legend Overlay
          Align(
            alignment: Alignment.bottomRight,
            child: Container(
              margin: const EdgeInsets.all(16),
              padding: const EdgeInsets.all(8),
              color: Colors.white.withOpacity(0.9),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: const [
                  Row(children: [Icon(Icons.location_on, color: Colors.green, size: 16), SizedBox(width: 4), Text("Normal")]),
                  SizedBox(height: 4),
                  Row(children: [Icon(Icons.location_on, color: Colors.redAccent, size: 16), SizedBox(width: 4), Text("Critical Alert")]),
                  SizedBox(height: 4),
                  Row(children: [Icon(Icons.location_on, color: Colors.grey, size: 16), SizedBox(width: 4), Text("Offline (>30s)")]),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showNodeDetails(BuildContext context, MeshNode node) {
    showModalBottomSheet(
      context: context,
      builder: (_) => Container(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              "Node #${node.id}", 
              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold)
            ),
            const Divider(),
            const SizedBox(height: 10),
            _detailRow(Icons.favorite, "Heart Rate", "${node.bpm} BPM"),
            _detailRow(Icons.air, "SpO2", "${node.spo2} %"),
            _detailRow(Icons.share, "Hops to here", "${node.lastHopCount}"),
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: node.isCritical ? Colors.red : Colors.green,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                node.isCritical ? "CRITICAL STATUS" : "STABLE",
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
              ),
            )
          ],
        ),
      ),
    );
  }

  Widget _detailRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        children: [
          Icon(icon, color: Colors.grey),
          const SizedBox(width: 16),
          Text(label, style: const TextStyle(fontSize: 16)),
          const Spacer(),
          Text(value, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
}