import 'package:flutter/material.dart';

class HourGridPainter extends CustomPainter {
  final double hourHeight;
  HourGridPainter({required this.hourHeight});

  @override
  void paint(Canvas canvas, Size size) {
    final double width = size.width;
    final paintDashed30 = Paint()
      ..color = Colors.grey.shade200
      ..strokeWidth = 1.0
      ..style = PaintingStyle.stroke;
    final paintDotted15 = Paint()
      ..color = Colors.grey.shade100
      ..strokeWidth = 1.2
      ..style = PaintingStyle.stroke;

    double y15 = hourHeight * 0.25;
    double startX15 = 0;
    while (startX15 < width) {
      canvas.drawCircle(Offset(startX15, y15), 0.6, paintDotted15);
      startX15 += 4.0;
    }
    double y30 = hourHeight * 0.5;
    double startX30 = 0;
    while (startX30 < width) {
      canvas.drawLine(
        Offset(startX30, y30),
        Offset(startX30 + 6.0, y30),
        paintDashed30,
      );
      startX30 += 10.0;
    }
    double y45 = hourHeight * 0.75;
    double startX45 = 0;
    while (startX45 < width) {
      canvas.drawCircle(Offset(startX45, y45), 0.6, paintDotted15);
      startX45 += 4.0;
    }
  }

  @override
  bool shouldRepaint(covariant HourGridPainter oldDelegate) {
    return oldDelegate.hourHeight != hourHeight;
  }
}
