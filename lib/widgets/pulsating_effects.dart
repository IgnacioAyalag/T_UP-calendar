import 'package:flutter/material.dart';

// --- PULSATING OVERDUE EFFECTS ---
class PulsatingTaskCard extends StatefulWidget {
  final Widget child;
  const PulsatingTaskCard({required this.child});

  @override
  _PulsatingTaskCardState createState() => _PulsatingTaskCardState();
}

class _PulsatingTaskCardState extends State<PulsatingTaskCard>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;
  late Animation<double> _glowRadius;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: 1100),
    )..repeat(reverse: true);
    _glowRadius = Tween<double>(begin: 2.0, end: 9.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _glowRadius,
      builder: (context, child) {
        return Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: Colors.red.withAlpha((0.35 * 255).round()),
                blurRadius: _glowRadius.value,
                spreadRadius: _glowRadius.value * 0.4,
              ),
            ],
          ),
          child: widget.child,
        );
      },
    );
  }
}

class PulsatingCalendarIcon extends StatefulWidget {
  final double size;
  const PulsatingCalendarIcon({this.size = 13.0});

  @override
  _PulsatingCalendarIconState createState() => _PulsatingCalendarIconState();
}

class _PulsatingCalendarIconState extends State<PulsatingCalendarIcon>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _opacityAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 450),
    )..repeat(reverse: true);
    _opacityAnimation = Tween<double>(begin: 0.55, end: 1.0).animate(
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
    return FadeTransition(
      opacity: _opacityAnimation,
      child: Icon(
        Icons.warning_rounded,
        color: Colors.red.shade700,
        size: widget.size,
      ),
    );
  }
}
