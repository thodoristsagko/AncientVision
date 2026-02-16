import 'dart:ui' as ui;
import 'package:flutter/material.dart';

class LiveChip extends StatelessWidget {
  final bool isConnected;
  final String status;

  const LiveChip({super.key, required this.isConnected, required this.status});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      child: ClipRRect(
        borderRadius: BorderRadius.circular(999),
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: 12, sigmaY: 12),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.white.withAlpha(36),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: Colors.white.withAlpha(89), width: 1),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 8, height: 8,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: isConnected ? const Color(0xFF4CAF50) : Colors.grey,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  isConnected ? 'LIVE' : 'OFFLINE',
                  style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class SafetyStatCard extends StatelessWidget {
  final String title;
  final String value;
  final String status;
  final Color? statusColor;

  const SafetyStatCard({
    super.key,
    required this.title,
    required this.value,
    required this.status,
    this.statusColor,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          height: 140,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: Colors.white.withAlpha(26),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: Colors.white.withAlpha(89), width: 1),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: TextStyle(color: Colors.white.withAlpha(217), fontSize: 13, fontWeight: FontWeight.w500)),
              const Spacer(),
              Text(value, style: const TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.w700)),
              const SizedBox(height: 4),
              Text(status, style: TextStyle(color: statusColor ?? Colors.white.withAlpha(191), fontSize: 12)),
            ],
          ),
        ),
      ),
    );
  }
}

class LiveSensorsCard extends StatelessWidget {
  final double accX, accY, accZ;
  final int moisturePercent;
  final String lastUpdate;
  final bool isConnected;
  final double vibration;
  final double ppv;
  final double dominantFreq;
  final double crestFactor;
  final double rms;
  final String hazardType;

  const LiveSensorsCard({
    super.key,
    required this.accX, required this.accY, required this.accZ,
    required this.moisturePercent, required this.lastUpdate, required this.isConnected,
    this.vibration = 0.0,
    this.ppv = 0.0,
    this.dominantFreq = 0.0,
    this.crestFactor = 0.0,
    this.rms = 0.0,
    this.hazardType = 'none',
  });

  @override
  Widget build(BuildContext context) {
    // DIN 4150-3 compliant status
    String vibStatus = 'Safe';
    Color vibColor = Colors.green;
    if (ppv > 10.0) {
      vibStatus = 'CRITICAL';
      vibColor = const Color(0xFFE53935);
    } else if (ppv > 3.0) {
      vibStatus = 'DIN EXCEEDED';
      vibColor = const Color(0xFFFF5722);
    } else if (ppv > 2.5) {
      vibStatus = 'Heritage limit';
      vibColor = Colors.orange;
    } else if (ppv > 0.3) {
      vibStatus = 'Perceptible';
      vibColor = const Color(0xFFFFC107);
    } else if (ppv == 0.0 && vibration > 0.5) {
      vibStatus = 'HIGH!';
      vibColor = Colors.red;
    } else if (ppv == 0.0 && vibration > 0.2) {
      vibStatus = 'Moderate';
      vibColor = Colors.orange;
    }

    final bool hasV2Data = ppv > 0 || rms > 0;

    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
          decoration: BoxDecoration(
            color: Colors.white.withAlpha(26),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: Colors.white.withAlpha(89), width: 1),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Text('Live sensors', style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600)),
                  const Spacer(),
                  if (hasV2Data)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: const Color(0xFF00BCD4).withAlpha(60),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Text('v2.0 DSP', style: TextStyle(color: Color(0xFF00BCD4), fontSize: 9, fontWeight: FontWeight.w600)),
                    ),
                  const SizedBox(width: 6),
                  Icon(
                    isConnected ? Icons.bluetooth_connected : Icons.bluetooth_disabled,
                    color: isConnected ? Colors.green : Colors.grey,
                    size: 18,
                  ),
                ],
              ),
              const SizedBox(height: 10),
              SensorRow(
                label: hasV2Data ? 'PPV (DIN 4150-3)' : 'Vibration (M5StickC)',
                value: hasV2Data
                    ? '${ppv.toStringAsFixed(1)} mm/s   Status: $vibStatus'
                    : '${vibration.toStringAsFixed(2)}g   Status: $vibStatus',
                icon: Icons.vibration,
                valueColor: vibColor,
              ),
              if (hasV2Data) ...[
                const SizedBox(height: 6),
                SensorRow(
                  label: 'Frequency analysis',
                  value: '${dominantFreq.toStringAsFixed(0)} Hz   Crest: ${crestFactor.toStringAsFixed(1)}   RMS: ${rms.toStringAsFixed(4)}g',
                  icon: Icons.graphic_eq,
                ),
              ],
              const SizedBox(height: 6),
              SensorRow(
                label: 'Soil moisture',
                value: '$moisturePercent %   (safe: 30-60%)',
                icon: Icons.water_drop_outlined,
              ),
              const SizedBox(height: 10),
              Text('Last update: $lastUpdate', style: TextStyle(color: Colors.white.withAlpha(179), fontSize: 11)),
            ],
          ),
        ),
      ),
    );
  }
}

class SensorRow extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color? valueColor;

  const SensorRow({super.key, required this.label, required this.value, required this.icon, this.valueColor});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 32, height: 32,
          decoration: BoxDecoration(
            color: Colors.white.withAlpha(20),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.white.withAlpha(89), width: 1),
          ),
          child: Icon(icon, size: 18, color: Colors.white),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w500)),
              const SizedBox(height: 2),
              Text(value, style: TextStyle(color: valueColor ?? Colors.white.withAlpha(204), fontSize: 11)),
            ],
          ),
        ),
      ],
    );
  }
}
