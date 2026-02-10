import 'package:flutter/material.dart';

/// Full-screen alert overlay for critical safety warnings
class FullScreenAlertOverlay extends StatefulWidget {
  final String message;
  final String level;
  final VoidCallback onDismiss;

  const FullScreenAlertOverlay({
    super.key,
    required this.message,
    required this.level,
    required this.onDismiss,
  });

  @override
  State<FullScreenAlertOverlay> createState() => _FullScreenAlertOverlayState();
}

class _FullScreenAlertOverlayState extends State<FullScreenAlertOverlay>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    )..repeat(reverse: true);
    _pulseAnimation = Tween<double>(begin: 0.8, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isCritical = widget.level == 'critical';
    final alertColor = isCritical ? const Color(0xFFE53935) : const Color(0xFFFFB300);

    return Material(
      color: Colors.transparent,
      child: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: BoxDecoration(
          gradient: RadialGradient(
            center: Alignment.center,
            radius: 1.5,
            colors: [
              alertColor.withAlpha(230),
              alertColor.withAlpha(200),
              Colors.black.withAlpha(240),
            ],
          ),
        ),
        child: SafeArea(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Pulsing icon
              AnimatedBuilder(
                animation: _pulseAnimation,
                builder: (context, child) {
                  return Transform.scale(
                    scale: _pulseAnimation.value,
                    child: Container(
                      width: 140,
                      height: 140,
                      decoration: BoxDecoration(
                        color: Colors.white.withAlpha(50),
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: alertColor.withAlpha(150),
                            blurRadius: 40,
                            spreadRadius: 20,
                          ),
                        ],
                      ),
                      child: Icon(
                        isCritical ? Icons.warning_rounded : Icons.error_outline,
                        size: 80,
                        color: Colors.white,
                      ),
                    ),
                  );
                },
              ),
              const SizedBox(height: 40),
              // Alert title
              Text(
                isCritical ? '⚠️ CRITICAL ALERT ⚠️' : '⚠️ WARNING',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 32,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 2,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              // Alert message
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.black.withAlpha(100),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.white.withAlpha(100), width: 2),
                  ),
                  child: Text(
                    widget.message,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 24,
                      fontWeight: FontWeight.w600,
                      height: 1.4,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              // Timestamp
              Text(
                'Detected at ${DateTime.now().hour.toString().padLeft(2, '0')}:${DateTime.now().minute.toString().padLeft(2, '0')}',
                style: TextStyle(
                  color: Colors.white.withAlpha(180),
                  fontSize: 16,
                ),
              ),
              const SizedBox(height: 48),
              // Action buttons
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Acknowledge button
                  GestureDetector(
                    onTap: widget.onDismiss,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 18),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(30),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withAlpha(80),
                            blurRadius: 12,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.check_circle, color: alertColor, size: 28),
                          const SizedBox(width: 12),
                          Text(
                            'ACKNOWLEDGE',
                            style: TextStyle(
                              color: alertColor,
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 1,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              // Safety instruction
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 48),
                child: Text(
                  isCritical
                      ? 'EVACUATE THE TRENCH IMMEDIATELY!\nFollow emergency protocol.'
                      : 'Check conditions and take appropriate action.',
                  style: TextStyle(
                    color: Colors.white.withAlpha(200),
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                    height: 1.5,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class CurrentAlertBanner extends StatelessWidget {
  final String level;
  final String message;

  const CurrentAlertBanner({super.key, required this.level, required this.message});

  @override
  Widget build(BuildContext context) {
    final isCritical = level == 'critical';
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isCritical ? Colors.red.withAlpha(77) : Colors.orange.withAlpha(77),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: isCritical ? Colors.red : Colors.orange, width: 2),
      ),
      child: Row(
        children: [
          Icon(
            isCritical ? Icons.warning_rounded : Icons.info_outline,
            color: isCritical ? Colors.red : Colors.orange,
            size: 28,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isCritical ? 'CRITICAL ALERT' : 'WARNING',
                  style: TextStyle(
                    color: isCritical ? Colors.red : Colors.orange,
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(message, style: const TextStyle(color: Colors.white, fontSize: 13)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
