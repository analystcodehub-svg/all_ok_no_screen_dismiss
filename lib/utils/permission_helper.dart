import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

class PermissionHelper {
  static Future<void> checkAndRequestNotificationPermission(BuildContext context) async {
    final status = await Permission.notification.status;
    
    if (!status.isGranted) {
      final newStatus = await Permission.notification.request();
      if (newStatus.isPermanentlyDenied) {
        // openAppSettings();
      }
    }
  }

  static Widget _buildPermissionBottomSheet(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 50,
              height: 5,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            const SizedBox(height: 24),
            const Icon(Icons.notifications_active_rounded, size: 60, color: Color(0xFF4F46E5)),
            const SizedBox(height: 16),
            const Text(
              'Allow Notifications',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Enable notifications so you never miss an incoming call or a new message.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 15,
                color: Colors.grey.shade600,
              ),
            ),
            const SizedBox(height: 32),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF4F46E5),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                onPressed: () async {
                  Navigator.pop(context);
                  final newStatus = await Permission.notification.request();
                  if (newStatus.isPermanentlyDenied) {
                    openAppSettings();
                  }
                },
                child: const Text('Allow', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
              ),
            ),
            const SizedBox(height: 12),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Maybe Later', style: TextStyle(color: Colors.grey, fontSize: 15)),
            ),
          ],
        ),
      ),
    );
  }

  static Future<bool> checkAndRequestMicrophonePermission() async {
    final status = await Permission.microphone.status;
    if (!status.isGranted) {
      final newStatus = await Permission.microphone.request();
      return newStatus.isGranted;
    }
    return true;
  }
}
