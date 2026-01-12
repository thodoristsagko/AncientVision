import 'dart:ui';
import 'package:flutter/material.dart';

/// Liquid glass effect widget with blur and transparency
/// Creates a premium glassmorphism UI effect
class LiquidGlass extends StatelessWidget {
  final Widget child;
  final double blur;
  final double opacity;
  final Color? color;
  final BorderRadius? borderRadius;
  final Border? border;
  final List<BoxShadow>? boxShadow;
  final EdgeInsets? padding;
  final EdgeInsets? margin;

  const LiquidGlass({
    super.key,
    required this.child,
    this.blur = 10.0,
    this.opacity = 0.15,
    this.color,
    this.borderRadius,
    this.border,
    this.boxShadow,
    this.padding,
    this.margin,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: margin,
      child: ClipRRect(
        borderRadius: borderRadius ?? BorderRadius.circular(16),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
          child: Container(
            padding: padding,
            decoration: BoxDecoration(
              color: color?.withValues(alpha: opacity) ??
                  Colors.white.withValues(alpha: opacity),
              borderRadius: borderRadius ?? BorderRadius.circular(16),
              border: border ??
                  Border.all(
                    color: Colors.white.withValues(alpha: 0.2),
                    width: 1.5,
                  ),
              boxShadow: boxShadow,
            ),
            child: child,
          ),
        ),
      ),
    );
  }
}

/// Premium liquid glass card
class LiquidGlassCard extends StatelessWidget {
  final Widget child;
  final EdgeInsets? padding;
  final EdgeInsets? margin;
  final Color? color;
  final VoidCallback? onTap;

  const LiquidGlassCard({
    super.key,
    required this.child,
    this.padding,
    this.margin,
    this.color,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    Widget content = LiquidGlass(
      blur: 15,
      opacity: 0.1,
      color: color,
      padding: padding ?? const EdgeInsets.all(20),
      margin: margin,
      borderRadius: BorderRadius.circular(24),
      border: Border.all(
        color: Colors.white.withValues(alpha: 0.3),
        width: 2,
      ),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.1),
          blurRadius: 20,
          offset: const Offset(0, 10),
        ),
      ],
      child: child,
    );

    if (onTap != null) {
      return GestureDetector(
        onTap: onTap,
        child: content,
      );
    }

    return content;
  }
}

/// Frosted glass app bar
class LiquidGlassAppBar extends StatelessWidget implements PreferredSizeWidget {
  final String title;
  final List<Widget>? actions;
  final Widget? leading;
  final bool automaticallyImplyLeading;

  const LiquidGlassAppBar({
    super.key,
    required this.title,
    this.actions,
    this.leading,
    this.automaticallyImplyLeading = true,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.3),
            border: Border(
              bottom: BorderSide(
                color: Colors.white.withValues(alpha: 0.1),
                width: 1,
              ),
            ),
          ),
          child: AppBar(
            title: Text(
              title,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 20,
              ),
            ),
            backgroundColor: Colors.transparent,
            elevation: 0,
            leading: leading,
            automaticallyImplyLeading: automaticallyImplyLeading,
            iconTheme: const IconThemeData(color: Colors.white),
            actions: actions,
          ),
        ),
      ),
    );
  }

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);
}

/// Liquid glass button
class LiquidGlassButton extends StatelessWidget {
  final String text;
  final VoidCallback onPressed;
  final IconData? icon;
  final Color? color;
  final bool isLoading;

  const LiquidGlassButton({
    super.key,
    required this.text,
    required this.onPressed,
    this.icon,
    this.color,
    this.isLoading = false,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: isLoading ? null : onPressed,
      child: LiquidGlass(
        blur: 20,
        opacity: 0.2,
        color: color ?? const Color(0xFF7C4DFF),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.4),
          width: 2,
        ),
        boxShadow: [
          BoxShadow(
            color: (color ?? const Color(0xFF7C4DFF)).withValues(alpha: 0.4),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
        child: Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (isLoading)
              const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation(Colors.white),
                ),
              )
            else if (icon != null)
              Icon(icon, color: Colors.white, size: 24),
            if (icon != null || isLoading) const SizedBox(width: 12),
            Text(
              text,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Frosted glass container with gradient
class GradientLiquidGlass extends StatelessWidget {
  final Widget child;
  final List<Color> gradientColors;
  final EdgeInsets? padding;
  final BorderRadius? borderRadius;

  const GradientLiquidGlass({
    super.key,
    required this.child,
    required this.gradientColors,
    this.padding,
    this.borderRadius,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: borderRadius ?? BorderRadius.circular(24),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
        child: Container(
          padding: padding ?? const EdgeInsets.all(20),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: gradientColors
                  .map((c) => c.withValues(alpha: 0.2))
                  .toList(),
            ),
            borderRadius: borderRadius ?? BorderRadius.circular(24),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.3),
              width: 2,
            ),
            boxShadow: [
              BoxShadow(
                color: gradientColors.first.withValues(alpha: 0.2),
                blurRadius: 30,
                offset: const Offset(0, 15),
              ),
            ],
          ),
          child: child,
        ),
      ),
    );
  }
}
