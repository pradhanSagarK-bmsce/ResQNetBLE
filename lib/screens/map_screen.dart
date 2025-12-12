import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'dart:math' as math;

class MapScreen extends StatefulWidget {
  const MapScreen({super.key});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  final MapController _mapController = MapController();
  
  // Default center (approx center of India)
  static const LatLng _defaultCenter = LatLng(20.5937, 78.9629);
  
  LatLng? _userLocation;
  bool _loadingLocation = true;
  String _locError = '';

  @override
  void initState() {
    super.initState();
    _initLocation();
  }

  Future<void> _initLocation() async {
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        setState(() {
           _locError = 'Location services are disabled.';
           _loadingLocation = false;
        });
        return;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
           setState(() {
             _locError = 'Location permissions are denied';
             _loadingLocation = false;
           });
           return;
        }
      }
      
      if (permission == LocationPermission.deniedForever) {
         setState(() {
           _locError = 'Location permissions are permanently denied';
           _loadingLocation = false;
         });
         return;
      }

      // Get current position
      Position position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high)
      );

      if (mounted) {
        setState(() {
          _userLocation = LatLng(position.latitude, position.longitude);
          _loadingLocation = false;
        });
        
        // If we found the user location, we might want to center on it initially
        // unless a specific device GPS was provided (handled in build).
      }
    } catch (e) {
      if (mounted) {
        setState(() {
           _locError = 'Error getting location: $e';
           _loadingLocation = false;
        });
      }
    }
  }

  // Basic Path Loss Model for Distance Estimation
  // d = 10 ^ ((TxPower - RSSI) / (10 * n))
  // We assume TxPower ~ -59 dBm at 1m, and n = 2.0 (Free space) to 4.0 (Indoors)
  // We'll use n=2.5 for a "likely" outdoor/mixed scenario.
  double _calculateDistance(int rssi) {
    if (rssi == 0) return 0.0;
    const int txPower = -59; 
    const double n = 2.5; 
    
    // RSSI is usually negative.
    // exp = (-59 - (-80)) / 25 = 21 / 25 = 0.84
    // d = 10^0.84 = ~6.9 meters
    
    double exponent = (txPower - rssi) / (10 * n);
    return math.pow(10, exponent).toDouble();
  }

  // Calculate distance between two LatLng points in meters
  String _formatGeoDistance(LatLng p1, LatLng p2) {
    const Distance distance = Distance();
    final double meter = distance.as(LengthUnit.Meter, p1, p2);
    if (meter > 1000) {
      return '${(meter / 1000).toStringAsFixed(2)} km';
    }
    return '${meter.toStringAsFixed(0)} m';
  }

  // Calculate bounding box for a circle
  LatLngBounds _getCircleBounds(LatLng center, double radiusMeters) {
    const Distance distance = Distance();
    
    // Calculate North, South, East, West points
    final north = distance.offset(center, radiusMeters, 0);
    final south = distance.offset(center, radiusMeters, 180);
    final east = distance.offset(center, radiusMeters, 90);
    final west = distance.offset(center, radiusMeters, 270);
    
    return LatLngBounds(
      LatLng(south.latitude, west.longitude),
      LatLng(north.latitude, east.longitude),
    );
  }

  void _zoomToFit(LatLng center, double? radiusMeters) {
      if (radiusMeters != null && radiusMeters > 0) {
          try {
             final bounds = _getCircleBounds(center, radiusMeters);
             _mapController.fitCamera(
               CameraFit.bounds(
                 bounds: bounds,
                 padding: const EdgeInsets.all(50), // Padding to ensure circle isn't touching edges
               ),
             );
          } catch (e) {
             // Fallback if bounds valid fails
             _mapController.move(center, 16.0);
          }
      } else {
          _mapController.move(center, 15.0);
      }
  }

  @override
  Widget build(BuildContext context) {
    final args = ModalRoute.of(context)?.settings.arguments as Map<String, dynamic>?;
    
    double? deviceLat = args?['lat'] as double?;
    double? deviceLon = args?['lon'] as double?;
    String? deviceLabel = args?['label'] as String?;
    int? rssi = args?['rssi'] as int?;
    
    final bool hasDeviceGps = deviceLat != null && deviceLon != null && (deviceLat != 0 || deviceLon != 0);
    final LatLng? devicePos = hasDeviceGps ? LatLng(deviceLat, deviceLon) : null;
    
    // We defer the initial move until after first frame to ensure map is ready for bounds
    // Or we can use initialCameraFit if supported, but initialCenter is easier.
    // We will use a post-frame callback if we need to fit bounds immediately.
    
    // For now, let's determine logic:
    LatLng showCenter = _defaultCenter;
    double? showRadius;
    
    if (devicePos != null) {
      showCenter = devicePos;
      // If we have both, maybe zoom to fit both?
      if (_userLocation != null) {
         // Create bounds including both points
         // We might implement that later, for now Focus on Device is good.
      }
    } else if (_userLocation != null) {
      showCenter = _userLocation!;
      if (rssi != null && rssi != 0) {
         showRadius = _calculateDistance(rssi);
      }
    }

    final markers = <Marker>[];
    final circles = <CircleMarker>[];

    // 1. User Marker (Blue)
    if (_userLocation != null) {
      markers.add(
        Marker(
          point: _userLocation!,
          width: 60,
          height: 60,
          child: Column(
            children: [
              Container(
                decoration: BoxDecoration(
                  color: Colors.blueAccent.withValues(alpha: 0.2),
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 2),
                  boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 4)],
                ),
                padding: const EdgeInsets.all(4),
                child: const Icon(Icons.my_location, color: Colors.blueAccent, size: 30),
              ),
              const Text('You', style: TextStyle(color: Colors.blue, fontWeight: FontWeight.bold, fontSize: 10, shadows: [Shadow(blurRadius: 2, color: Colors.white)])),
            ],
          ),
        ),
      );

      // 2. RSSI Probability Circle (around User)
      if (showRadius != null) {
        circles.add(
          CircleMarker(
            point: _userLocation!,
            color: Colors.blue.withValues(alpha:0.1),
            borderColor: Colors.blue.withValues(alpha:0.6),
            borderStrokeWidth: 3, // Thicker border as requested
            useRadiusInMeter: true,
            radius: showRadius,
          ),
        );
      }
    }

    // 3. Device Marker (Red)
    if (devicePos != null) {
      markers.add(
        Marker(
          point: devicePos,
          width: 80,
          height: 80,
          child: Column(
            children: [
               const Icon(Icons.location_on, color: Colors.redAccent, size: 40),
               Container(
                 padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                 decoration: BoxDecoration(
                   color: Colors.black87,
                   borderRadius: BorderRadius.circular(6),
                   border: Border.all(color: Colors.white24),
                 ),
                 child: Text(
                   deviceLabel ?? 'Device', 
                   style: const TextStyle(fontSize: 11, color: Colors.white, fontWeight: FontWeight.bold),
                   overflow: TextOverflow.ellipsis,
                 ),
               ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Rescue Map')),
      body: Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: showCenter,
              initialZoom: 15.0, // Default, will be overridden by onMapReady if we add it
              onMapReady: () {
                 // Auto-fit logic when map is ready
                 if (showRadius != null && devicePos == null) {
                    _zoomToFit(showCenter, showRadius);
                 } else if (devicePos != null && _userLocation != null) {
                    // Fit both points
                    _mapController.fitCamera(
                      CameraFit.bounds(
                        bounds: LatLngBounds.fromPoints([devicePos, _userLocation!]),
                        padding: const EdgeInsets.all(50),
                      )
                    );
                 } else if (devicePos != null) {
                    _mapController.move(devicePos, 16.0);
                 }
              },
              interactionOptions: const InteractionOptions(
                flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
              ),
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png',
                subdomains: const ['a', 'b', 'c'],
                userAgentPackageName: 'com.example.resqnet_ble', // Good practice for OSM
              ),
              CircleLayer(circles: circles),
              MarkerLayer(markers: markers),
            ],
          ),
          
          // --- OVERLAYS ---
          
          // 1. Compass (Top Right)
          Positioned(
            top: 20,
            right: 20,
            child: Container(
              decoration: BoxDecoration(
                 color: Colors.white,
                 shape: BoxShape.circle,
                 boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 4)],
              ),
              child: IconButton(
                icon: const Icon(Icons.explore, color: Colors.indigo, size: 32),
                onPressed: () {
                   // Reset North
                   _mapController.rotate(0);
                },
                tooltip: 'Reset North',
              ),
            ),
          ),

          // 2. Info Card (Bottom Center)
          Positioned(
            bottom: 30, // Above FAB/Attribution
            left: 20,
            right: 80, // Leave space for FAB
            child: Card(
              color: Colors.black87.withValues(alpha:0.85),
              elevation: 6,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              child: Padding(
                padding: const EdgeInsets.all(12.0),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _buildCoordRow('You', _userLocation),
                    if (devicePos != null) ...[
                       const Divider(color: Colors.white24, height: 12),
                       _buildCoordRow(deviceLabel ?? 'Device', devicePos, isDevice: true),
                    ],
                    
                    if (showRadius != null) ...[
                       const Divider(color: Colors.white24, height: 12),
                       Row(
                         children: [
                            const Icon(Icons.radar, color: Colors.blueAccent, size: 16),
                            const SizedBox(width: 8),
                            Expanded(child: Text('Search Radius: ${_calculateDistance(rssi!).toStringAsFixed(1)} m', style: const TextStyle(color: Colors.blueAccent, fontWeight: FontWeight.bold))),
                            Text('${rssi} dBm', style: TextStyle(color: _calculateDistance(rssi) < 20 ? Colors.green : Colors.orange, fontSize: 12)),
                         ],
                       )
                    ],

                    if (_userLocation != null && devicePos != null) ...[
                       const Divider(color: Colors.white24, height: 12),
                       Row(
                           mainAxisAlignment: MainAxisAlignment.center,
                           children: [
                              const Icon(Icons.straighten, color: Colors.amber, size: 16),
                              const SizedBox(width: 8),
                              Text(
                                '${_formatGeoDistance(_userLocation!, devicePos)}',
                                style: const TextStyle(color: Colors.amber, fontWeight: FontWeight.bold, fontSize: 16),
                              )
                           ],
                         ),
                    ],

                    if (_loadingLocation)
                       const Padding(
                         padding: EdgeInsets.only(top: 8.0),
                         child: LinearProgressIndicator(minHeight: 2),
                       ),
                  ],
                ),
              ),
            ),
          ),
          
          if (_locError.isNotEmpty)
             Positioned(
               top: 80,
               left: 20, 
               right: 20,
               child: Container(
                 padding: const EdgeInsets.all(12),
                 decoration: BoxDecoration(color: Colors.redAccent, borderRadius: BorderRadius.circular(8)),
                 child: Row(
                    children: [
                        const Icon(Icons.error_outline, color: Colors.white),
                        const SizedBox(width: 12),
                        Expanded(child: Text(_locError, style: const TextStyle(color: Colors.white))),
                    ]
                 ),
               ),
             ),
        ],
      ),
      floatingActionButton: Column(
         mainAxisAlignment: MainAxisAlignment.end,
         children: [
             if (showRadius != null && devicePos == null)
                FloatingActionButton(
                   mini: true,
                   heroTag: 'zoom_fit',
                   backgroundColor: Colors.white,
                   child: const Icon(Icons.center_focus_weak, color: Colors.indigo),
                   onPressed: () => _zoomToFit(showCenter, showRadius),
                ),
             const SizedBox(height: 8),
             FloatingActionButton(
                heroTag: 'my_loc',
                backgroundColor: Colors.indigo,
                child: const Icon(Icons.my_location, color: Colors.white),
                onPressed: () {
                    if (_userLocation != null) {
                      _mapController.move(_userLocation!, 16.0);
                    } else {
                      _initLocation();
                    }
                },
              ),
         ],
      ),
    );
  }

  Widget _buildCoordRow(String label, LatLng? pos, {bool isDevice = false}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Row(
          children: [
            Icon(
              isDevice ? Icons.location_on : Icons.person_pin_circle,
              color: isDevice ? Colors.redAccent : Colors.blueAccent,
              size: 18,
            ),
            const SizedBox(width: 8),
            Text(label, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
          ],
        ),
        Text(
          pos != null 
             ? '${pos.latitude.toStringAsFixed(5)}, ${pos.longitude.toStringAsFixed(5)}'
             : 'Finding...',
          style: TextStyle(
            color: pos != null ? Colors.white : Colors.white24,
            fontFamily: 'monospace',
            fontSize: 12
          ),
        ),
      ],
    );
  }
}
