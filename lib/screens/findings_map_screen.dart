import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:http/http.dart' as http;
import '../models/finding_model.dart';

class FindingsMap extends StatefulWidget {
  final List<Finding> findings;
  final int selectedIndex;

  const FindingsMap({
    super.key,
    required this.findings,
    required this.selectedIndex,
  });

  @override
  State<FindingsMap> createState() => _FindingsMapState();
}

class _FindingsMapState extends State<FindingsMap> {
  MapController? _mapController;
  String _locationName = 'Archaeological Site';
  bool _isLoadingLocation = false;

  @override
  void initState() {
    super.initState();
    _mapController = MapController();
    // Load initial location name
    if (widget.findings.isNotEmpty) {
      _reverseGeocode(widget.findings.first.latitude, widget.findings.first.longitude);
    }
  }

  @override
  void didUpdateWidget(covariant FindingsMap oldWidget) {
    super.didUpdateWidget(oldWidget);
    // When selectedIndex changes, move map to that finding
    if (oldWidget.selectedIndex != widget.selectedIndex && widget.findings.isNotEmpty) {
      final selected = widget.findings[widget.selectedIndex];
      _mapController?.move(
        LatLng(selected.latitude, selected.longitude),
        17.5,
      );
      // Update location name for the new position
      _reverseGeocode(selected.latitude, selected.longitude);
    }
  }

  Future<void> _reverseGeocode(double lat, double lon) async {
    if (_isLoadingLocation) return;
    setState(() => _isLoadingLocation = true);

    try {
      final url = Uri.parse(
        'https://nominatim.openstreetmap.org/reverse?format=json&lat=$lat&lon=$lon&zoom=18&addressdetails=1',
      );
      final response = await http.get(url, headers: {
        'User-Agent': 'AncientVision-FLL-App/1.0',
      });

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final address = data['address'] as Map<String, dynamic>?;

        // Try to get a meaningful location name
        String name = data['name'] as String? ?? '';
        if (name.isEmpty) {
          name = address?['historic'] as String? ??
                 address?['tourism'] as String? ??
                 address?['archaeological_site'] as String? ??
                 address?['amenity'] as String? ??
                 address?['suburb'] as String? ??
                 address?['neighbourhood'] as String? ??
                 address?['village'] as String? ??
                 address?['town'] as String? ??
                 address?['city'] as String? ??
                 'Archaeological Site';
        }

        if (mounted) {
          setState(() => _locationName = name);
        }
      }
    } catch (e) {
      // Keep the default name on error
    } finally {
      if (mounted) {
        setState(() => _isLoadingLocation = false);
      }
    }
  }

  Future<void> _openInGoogleMaps() async {
    final center = widget.findings[widget.selectedIndex];
    final url = Uri.parse(
      'https://www.google.com/maps/search/?api=1&query=${center.latitude},${center.longitude}',
    );
    if (await canLaunchUrl(url)) {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    }
  }

  List<Marker> _buildMarkers() {
    return widget.findings.asMap().entries.map((entry) {
      final index = entry.key;
      final finding = entry.value;
      final isSelected = index == widget.selectedIndex;
      final typeColor = Finding.getTypeColor(finding.type);

      return Marker(
        point: LatLng(finding.latitude, finding.longitude),
        width: isSelected ? 48 : 36,
        height: isSelected ? 48 : 36,
        child: GestureDetector(
          onTap: () => _openInGoogleMaps(),
          child: Stack(
            alignment: Alignment.center,
            children: [
              // Outer glow for selected marker
              if (isSelected)
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: typeColor.withAlpha(77),
                  ),
                ),
              // Main marker icon
              Icon(
                Icons.location_pin,
                size: isSelected ? 40 : 32,
                color: isSelected ? typeColor : typeColor.withAlpha(217),
                shadows: [
                  Shadow(
                    color: Colors.black.withAlpha(128),
                    blurRadius: 4,
                  ),
                ],
              ),
              // Type indicator dot
              Positioned(
                top: isSelected ? 8 : 4,
                child: Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                    border: Border.all(color: typeColor, width: 2),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    // Center on the most recent finding (first in the list)
    final firstFinding = widget.findings.first;

    return Stack(
      children: [
        // Interactive OpenStreetMap
        FlutterMap(
          mapController: _mapController,
          options: MapOptions(
            initialCenter: LatLng(firstFinding.latitude, firstFinding.longitude),
            initialZoom: 17.5,
            minZoom: 10,
            maxZoom: 19,
            interactionOptions: const InteractionOptions(
              flags: InteractiveFlag.all,
            ),
          ),
          children: [
            TileLayer(
              urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
              userAgentPackageName: 'com.example.ancient_vision',
            ),
            MarkerLayer(
              markers: _buildMarkers(),
            ),
          ],
        ),

        // Map label overlay - dynamic location name
        Positioned(
          top: 12,
          left: 12,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.black.withAlpha(179),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_isLoadingLocation)
                  const Padding(
                    padding: EdgeInsets.only(right: 6),
                    child: SizedBox(
                      width: 10,
                      height: 10,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(Color(0xFFFFC107)),
                      ),
                    ),
                  ),
                Text(
                  _locationName,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),

        // Open in Google Maps button
        Positioned(
          bottom: 12,
          right: 12,
          child: GestureDetector(
            onTap: _openInGoogleMaps,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFFFFC107),
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withAlpha(77),
                    blurRadius: 8,
                    spreadRadius: 1,
                  ),
                ],
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.open_in_new,
                    color: Color(0xFF3E2723),
                    size: 16,
                  ),
                  SizedBox(width: 6),
                  Text(
                    'Open in Google Maps',
                    style: TextStyle(
                      color: Color(0xFF3E2723),
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  @override
  void dispose() {
    _mapController?.dispose();
    super.dispose();
  }
}
