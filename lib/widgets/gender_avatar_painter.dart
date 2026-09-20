import 'dart:math' as math;
import 'package:flutter/material.dart';

// ─── Male Avatar ─────────────────────────────────────────────────────────────

class MaleAvatarPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height * 0.38;
    final r = size.width * 0.30;

    // Skin
    final skinPaint = Paint()..color = const Color(0xFFFFCBA4);
    // Dark hair
    final hairPaint = Paint()..color = const Color(0xFF1A1A2E);
    // Shadow/depth
    final shadowPaint = Paint()..color = const Color(0xFFE8A87C);
    // Body shirt — navy blue
    final shirtPaint = Paint()
      ..shader = const LinearGradient(
        colors: [Color(0xFF1565C0), Color(0xFF0D47A1)],
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
      ).createShader(Rect.fromLTWH(0, size.height * 0.6, size.width, size.height * 0.4));

    // ── Body / shoulders ──
    final bodyPath = Path()
      ..moveTo(cx - size.width * 0.42, size.height)
      ..lineTo(cx - size.width * 0.28, size.height * 0.62)
      ..quadraticBezierTo(cx - size.width * 0.15, size.height * 0.58, cx, size.height * 0.57)
      ..quadraticBezierTo(cx + size.width * 0.15, size.height * 0.58, cx + size.width * 0.28, size.height * 0.62)
      ..lineTo(cx + size.width * 0.42, size.height)
      ..close();
    canvas.drawPath(bodyPath, shirtPaint);

    // Collar / neck
    final neckPaint = Paint()..color = const Color(0xFFFFCBA4);
    canvas.drawRect(
      Rect.fromLTWH(cx - size.width * 0.07, size.height * 0.55, size.width * 0.14, size.height * 0.09),
      neckPaint,
    );

    // ── Head ──
    canvas.drawCircle(Offset(cx, cy), r, skinPaint);

    // Jaw shadow
    final jawShadow = Paint()..color = const Color(0xFFE8A87C);
    canvas.drawArc(
      Rect.fromCircle(center: Offset(cx, cy + r * 0.3), radius: r * 0.75),
      0, math.pi, false, jawShadow..style = PaintingStyle.fill,
    );

    // ── Hair (short, styled) ──
    final hairPath = Path()
      ..moveTo(cx - r * 0.95, cy - r * 0.2)
      ..quadraticBezierTo(cx - r * 1.0, cy - r * 1.05, cx, cy - r * 1.1)
      ..quadraticBezierTo(cx + r * 1.0, cy - r * 1.05, cx + r * 0.95, cy - r * 0.2)
      ..quadraticBezierTo(cx + r * 0.8, cy - r * 0.6, cx, cy - r * 0.65)
      ..quadraticBezierTo(cx - r * 0.8, cy - r * 0.6, cx - r * 0.95, cy - r * 0.2)
      ..close();
    canvas.drawPath(hairPath, hairPaint);

    // Side burns
    canvas.drawRect(Rect.fromLTWH(cx - r, cy - r * 0.1, r * 0.15, r * 0.4), hairPaint);
    canvas.drawRect(Rect.fromLTWH(cx + r * 0.85, cy - r * 0.1, r * 0.15, r * 0.4), hairPaint);

    // ── Eyes ──
    final eyePaint = Paint()..color = const Color(0xFF1A1A2E);
    // Left eye
    canvas.drawOval(Rect.fromCenter(center: Offset(cx - r * 0.38, cy - r * 0.08), width: r * 0.28, height: r * 0.2), eyePaint);
    // Right eye
    canvas.drawOval(Rect.fromCenter(center: Offset(cx + r * 0.38, cy - r * 0.08), width: r * 0.28, height: r * 0.2), eyePaint);
    // Eye shine
    final shinePaint = Paint()..color = Colors.white;
    canvas.drawCircle(Offset(cx - r * 0.33, cy - r * 0.12), r * 0.06, shinePaint);
    canvas.drawCircle(Offset(cx + r * 0.43, cy - r * 0.12), r * 0.06, shinePaint);

    // ── Eyebrows (thick, sharp) ──
    final browPaint = Paint()
      ..color = const Color(0xFF1A1A2E)
      ..strokeWidth = r * 0.09
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    canvas.drawLine(
      Offset(cx - r * 0.52, cy - r * 0.28),
      Offset(cx - r * 0.22, cy - r * 0.24),
      browPaint,
    );
    canvas.drawLine(
      Offset(cx + r * 0.22, cy - r * 0.24),
      Offset(cx + r * 0.52, cy - r * 0.28),
      browPaint,
    );

    // ── Nose ──
    final nosePaint = Paint()
      ..color = shadowPaint.color
      ..style = PaintingStyle.fill;
    canvas.drawOval(Rect.fromCenter(center: Offset(cx, cy + r * 0.18), width: r * 0.2, height: r * 0.14), nosePaint);

    // ── Smile (subtle smirk) ──
    final smilePaint = Paint()
      ..color = const Color(0xFFB07050)
      ..strokeWidth = r * 0.07
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    final smilePath = Path()
      ..moveTo(cx - r * 0.28, cy + r * 0.38)
      ..quadraticBezierTo(cx, cy + r * 0.52, cx + r * 0.28, cy + r * 0.38);
    canvas.drawPath(smilePath, smilePaint);

    // ── Beard stubble ──
    final stubblePaint = Paint()..color = const Color(0xFF1A1A2E).withValues(alpha: 0.18);
    canvas.drawOval(
      Rect.fromCenter(center: Offset(cx, cy + r * 0.48), width: r * 0.85, height: r * 0.35),
      stubblePaint,
    );

    // ── Ears ──
    canvas.drawOval(Rect.fromCenter(center: Offset(cx - r, cy + r * 0.05), width: r * 0.22, height: r * 0.32), skinPaint);
    canvas.drawOval(Rect.fromCenter(center: Offset(cx + r, cy + r * 0.05), width: r * 0.22, height: r * 0.32), skinPaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// ─── Female Avatar ───────────────────────────────────────────────────────────

class FemaleAvatarPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height * 0.36;
    final r = size.width * 0.28;

    // Skin
    final skinPaint = Paint()..color = const Color(0xFFFFD5B8);
    // Shadow
    final shadowPaint = Paint()..color = const Color(0xFFEEB896);
    // Hair — dark with warm brown
    final hairPaint = Paint()..color = const Color(0xFF3B1F0A);
    // Dress — elegant deep red/rose
    final dressPaint = Paint()
      ..shader = const LinearGradient(
        colors: [Color(0xFFAD1457), Color(0xFF6A0032)],
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
      ).createShader(Rect.fromLTWH(0, size.height * 0.58, size.width, size.height * 0.42));

    // ── Long Hair (back layer) ──
    final backHairPaint = Paint()..color = const Color(0xFF2A1205);
    final backHairPath = Path()
      ..moveTo(cx - r * 1.1, cy - r * 0.5)
      ..quadraticBezierTo(cx - r * 1.4, cy + r * 1.5, cx - r * 0.9, size.height * 0.85)
      ..lineTo(cx + r * 0.9, size.height * 0.85)
      ..quadraticBezierTo(cx + r * 1.4, cy + r * 1.5, cx + r * 1.1, cy - r * 0.5)
      ..close();
    canvas.drawPath(backHairPath, backHairPaint);

    // ── Body / dress ──
    final bodyPath = Path()
      ..moveTo(cx - size.width * 0.45, size.height)
      ..lineTo(cx - size.width * 0.22, size.height * 0.60)
      ..quadraticBezierTo(cx - size.width * 0.10, size.height * 0.56, cx, size.height * 0.555)
      ..quadraticBezierTo(cx + size.width * 0.10, size.height * 0.56, cx + size.width * 0.22, size.height * 0.60)
      ..lineTo(cx + size.width * 0.45, size.height)
      ..close();
    canvas.drawPath(bodyPath, dressPaint);

    // Neck
    canvas.drawRect(
      Rect.fromLTWH(cx - size.width * 0.06, size.height * 0.53, size.width * 0.12, size.height * 0.09),
      skinPaint,
    );

    // ── Head ──
    // Slightly oval (feminine face)
    canvas.drawOval(Rect.fromCenter(center: Offset(cx, cy), width: r * 2.0, height: r * 2.2), skinPaint);

    // Chin shadow
    canvas.drawOval(
      Rect.fromCenter(center: Offset(cx, cy + r * 0.65), width: r * 1.5, height: r * 0.6),
      shadowPaint,
    );

    // ── Hair top ──
    final hairTopPath = Path()
      ..moveTo(cx - r * 1.0, cy - r * 0.15)
      ..quadraticBezierTo(cx - r * 1.0, cy - r * 1.35, cx, cy - r * 1.38)
      ..quadraticBezierTo(cx + r * 1.0, cy - r * 1.35, cx + r * 1.0, cy - r * 0.15)
      ..quadraticBezierTo(cx + r * 0.7, cy - r * 0.55, cx, cy - r * 0.6)
      ..quadraticBezierTo(cx - r * 0.7, cy - r * 0.55, cx - r * 1.0, cy - r * 0.15)
      ..close();
    canvas.drawPath(hairTopPath, hairPaint);

    // Side sweep (left)
    final sideHairL = Path()
      ..moveTo(cx - r * 1.0, cy - r * 0.15)
      ..quadraticBezierTo(cx - r * 1.2, cy + r * 0.6, cx - r * 1.0, cy + r * 1.1)
      ..lineTo(cx - r * 0.85, cy + r * 1.0)
      ..quadraticBezierTo(cx - r * 0.9, cy + r * 0.5, cx - r * 0.85, cy - r * 0.1)
      ..close();
    canvas.drawPath(sideHairL, hairPaint);

    // Side sweep (right)
    final sideHairR = Path()
      ..moveTo(cx + r * 1.0, cy - r * 0.15)
      ..quadraticBezierTo(cx + r * 1.2, cy + r * 0.6, cx + r * 1.0, cy + r * 1.1)
      ..lineTo(cx + r * 0.85, cy + r * 1.0)
      ..quadraticBezierTo(cx + r * 0.9, cy + r * 0.5, cx + r * 0.85, cy - r * 0.1)
      ..close();
    canvas.drawPath(sideHairR, hairPaint);

    // ── Ears ──
    canvas.drawOval(Rect.fromCenter(center: Offset(cx - r, cy + r * 0.05), width: r * 0.22, height: r * 0.3), skinPaint);
    canvas.drawOval(Rect.fromCenter(center: Offset(cx + r, cy + r * 0.05), width: r * 0.22, height: r * 0.3), skinPaint);

    // Earrings (small gold circles)
    final earringPaint = Paint()..color = const Color(0xFFFFD700);
    canvas.drawCircle(Offset(cx - r * 1.02, cy + r * 0.28), r * 0.08, earringPaint);
    canvas.drawCircle(Offset(cx + r * 1.02, cy + r * 0.28), r * 0.08, earringPaint);

    // ── Eyes (large, with lashes) ──
    final eyeWhitePaint = Paint()..color = Colors.white;
    final eyePaint = Paint()..color = const Color(0xFF3E2723);
    final lashPaint = Paint()
      ..color = const Color(0xFF1A1A1A)
      ..strokeWidth = r * 0.06
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    // Left eye
    canvas.drawOval(Rect.fromCenter(center: Offset(cx - r * 0.36, cy - r * 0.08), width: r * 0.38, height: r * 0.26), eyeWhitePaint);
    canvas.drawOval(Rect.fromCenter(center: Offset(cx - r * 0.36, cy - r * 0.06), width: r * 0.22, height: r * 0.22), eyePaint);
    // Right eye
    canvas.drawOval(Rect.fromCenter(center: Offset(cx + r * 0.36, cy - r * 0.08), width: r * 0.38, height: r * 0.26), eyeWhitePaint);
    canvas.drawOval(Rect.fromCenter(center: Offset(cx + r * 0.36, cy - r * 0.06), width: r * 0.22, height: r * 0.22), eyePaint);
    // Shine
    final shinePaint = Paint()..color = Colors.white;
    canvas.drawCircle(Offset(cx - r * 0.30, cy - r * 0.10), r * 0.06, shinePaint);
    canvas.drawCircle(Offset(cx + r * 0.42, cy - r * 0.10), r * 0.06, shinePaint);

    // Lashes (top left)
    for (int i = 0; i < 5; i++) {
      final angle = math.pi + (i * 0.18) - 0.36;
      final lx = cx - r * 0.36 + math.cos(angle) * r * 0.2;
      final ly = (cy - r * 0.08) + math.sin(angle) * r * 0.14;
      canvas.drawLine(Offset(lx, ly), Offset(lx + math.cos(angle) * r * 0.1, ly + math.sin(angle) * r * 0.1), lashPaint);
    }
    // Lashes (top right)
    for (int i = 0; i < 5; i++) {
      final angle = math.pi + (i * 0.18) - 0.36;
      final lx = cx + r * 0.36 - math.cos(angle) * r * 0.2;
      final ly = (cy - r * 0.08) + math.sin(angle) * r * 0.14;
      canvas.drawLine(Offset(lx, ly), Offset(lx - math.cos(angle) * r * 0.1, ly + math.sin(angle) * r * 0.1), lashPaint);
    }

    // ── Eyebrows (arched, feminine) ──
    final browPaint = Paint()
      ..color = const Color(0xFF3B1F0A)
      ..strokeWidth = r * 0.07
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    final leftBrow = Path()
      ..moveTo(cx - r * 0.55, cy - r * 0.33)
      ..quadraticBezierTo(cx - r * 0.35, cy - r * 0.44, cx - r * 0.18, cy - r * 0.32);
    canvas.drawPath(leftBrow, browPaint);
    final rightBrow = Path()
      ..moveTo(cx + r * 0.18, cy - r * 0.32)
      ..quadraticBezierTo(cx + r * 0.35, cy - r * 0.44, cx + r * 0.55, cy - r * 0.33);
    canvas.drawPath(rightBrow, browPaint);

    // ── Nose (tiny, feminine) ──
    final nosePaint = Paint()
      ..color = shadowPaint.color
      ..style = PaintingStyle.fill;
    canvas.drawOval(Rect.fromCenter(center: Offset(cx, cy + r * 0.22), width: r * 0.16, height: r * 0.12), nosePaint);

    // ── Lips (full, red) ──
    final lipPaint = Paint()..color = const Color(0xFFD81B60);
    // Upper lip
    final upperLip = Path()
      ..moveTo(cx - r * 0.28, cy + r * 0.44)
      ..quadraticBezierTo(cx - r * 0.14, cy + r * 0.36, cx, cy + r * 0.40)
      ..quadraticBezierTo(cx + r * 0.14, cy + r * 0.36, cx + r * 0.28, cy + r * 0.44)
      ..quadraticBezierTo(cx, cy + r * 0.42, cx - r * 0.28, cy + r * 0.44)
      ..close();
    canvas.drawPath(upperLip, lipPaint);
    // Lower lip
    final lowerLip = Path()
      ..moveTo(cx - r * 0.28, cy + r * 0.44)
      ..quadraticBezierTo(cx, cy + r * 0.64, cx + r * 0.28, cy + r * 0.44)
      ..quadraticBezierTo(cx, cy + r * 0.58, cx - r * 0.28, cy + r * 0.44)
      ..close();
    canvas.drawPath(lowerLip, lipPaint);
    // Lip shine
    canvas.drawOval(
      Rect.fromCenter(center: Offset(cx, cy + r * 0.50), width: r * 0.18, height: r * 0.07),
      Paint()..color = Colors.white.withValues(alpha: 0.3),
    );

    // ── Blush ──
    final blushPaint = Paint()..color = const Color(0xFFFF8A80).withValues(alpha: 0.3);
    canvas.drawOval(Rect.fromCenter(center: Offset(cx - r * 0.6, cy + r * 0.22), width: r * 0.4, height: r * 0.2), blushPaint);
    canvas.drawOval(Rect.fromCenter(center: Offset(cx + r * 0.6, cy + r * 0.22), width: r * 0.4, height: r * 0.2), blushPaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// ─── Wrapper Widgets ──────────────────────────────────────────────────────────

class MaleAvatarWidget extends StatelessWidget {
  final double size;
  const MaleAvatarWidget({super.key, this.size = 120});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(painter: MaleAvatarPainter()),
    );
  }
}

class FemaleAvatarWidget extends StatelessWidget {
  final double size;
  const FemaleAvatarWidget({super.key, this.size = 120});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(painter: FemaleAvatarPainter()),
    );
  }
}

