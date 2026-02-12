import 'dart:ui' as ui;
import 'package:flutter/material.dart';

class GlassBottomNavBar extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onItemSelected;
  final bool isMuted;
  final VoidCallback onToggleMute;

  const GlassBottomNavBar({
    super.key,
    required this.currentIndex,
    required this.onItemSelected,
    required this.isMuted,
    required this.onToggleMute,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          height: 70,
          padding: const EdgeInsets.symmetric(horizontal: 20),
          decoration: BoxDecoration(
            color: Colors.white.withAlpha(26),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: Colors.white.withAlpha(89),
              width: 1,
            ),
          ),
          child: Row(
            children: [
              NavItem(
                icon: Icons.home_rounded,
                label: 'Home',
                index: 0,
                isSelected: currentIndex == 0,
                onTap: onItemSelected,
              ),
              NavItem(
                icon: Icons.article_rounded,
                label: 'Findings',
                index: 1,
                isSelected: currentIndex == 1,
                onTap: onItemSelected,
              ),
              NavItem(
                icon: Icons.apps_rounded,
                label: 'Tools',
                index: 2,
                isSelected: currentIndex == 2,
                onTap: onItemSelected,
              ),
              NavItem(
                icon: Icons.shield_rounded,
                label: 'Monitor',
                index: 3,
                isSelected: currentIndex == 3,
                onTap: onItemSelected,
              ),
              const SizedBox(width: 4),
              // Global mute button
              GestureDetector(
                onTap: onToggleMute,
                child: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: isMuted
                        ? Colors.red.withAlpha(77)
                        : Colors.green.withAlpha(77),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    isMuted ? Icons.volume_off_rounded : Icons.volume_up_rounded,
                    color: isMuted ? Colors.red.shade300 : Colors.green.shade300,
                    size: 20,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class NavItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final int index;
  final bool isSelected;
  final ValueChanged<int> onTap;

  const NavItem({
    super.key,
    required this.icon,
    required this.label,
    required this.index,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = isSelected ? Colors.white : Colors.white70;

    return Expanded(
      child: InkWell(
        onTap: () => onTap(index),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 22, color: color),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                color: color,
                fontSize: 11,
                fontWeight:
                    isSelected ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
