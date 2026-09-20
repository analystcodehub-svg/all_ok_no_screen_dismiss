import 'package:flutter/services.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:auto_start_flutter/auto_start_flutter.dart' as auto_start;

class AutoStartHelper {
  static Future<void> checkAndRequestAutoStart(BuildContext context) async {
    // 1. Request Notification Permission first (no dialog needed, OS shows it)
    var notifStatus = await Permission.notification.status;
    if (!notifStatus.isGranted) {
      await Permission.notification.request();
    }

    // 2. Request Display Over Other Apps
    var alertStatus = await Permission.systemAlertWindow.status;
    if (!alertStatus.isGranted) {
      if (!context.mounted) return;
      
      // Show a dialog to explain why we need it
      showDialog(
        context: context,
        builder: (BuildContext context) {
          return AlertDialog(
            title: const Text('Call Screen Permission'),
            content: const Text(
                'To reliably receive ringtones and incoming call screens even when the app is closed, please allow "Display over other apps".'),
            actions: [
              TextButton(
                child: const Text('Cancel'),
                onPressed: () {
                  Navigator.of(context).pop();
                },
              ),
              ElevatedButton(
                child: const Text('Open Settings'),
                onPressed: () async {
                  Navigator.of(context).pop();
                  
                  // Request the permission (blocks until the user leaves the settings screen)
                  await Permission.systemAlertWindow.request();
                  
                  // Once the user leaves the settings screen (either by pressing back or granting it),
                  // forcefully bring the app back to the foreground so they don't get stuck in Android Settings.
                  try {
                    const platform = MethodChannel('com.sajnire.app/auth');
                    await platform.invokeMethod('bringToForeground');
                  } catch (e) {
                    debugPrint('Failed to bring app to foreground: $e');
                  }
                },
              ),
            ],
          );
        },
      );
    }
  }
}
