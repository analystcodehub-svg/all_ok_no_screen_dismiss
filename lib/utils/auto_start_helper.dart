import 'package:auto_start_flutter/auto_start_flutter.dart';
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';

class AutoStartHelper {
  static Future<void> checkAndRequestAutoStart(BuildContext context) async {
    try {
      var isAvailable = await isAutoStartAvailable;
      if (isAvailable == true) {
        if (!context.mounted) return;
        
        // Show a dialog to explain why we need it
        showDialog(
          context: context,
          builder: (BuildContext context) {
            return AlertDialog(
              title: const Text('Background Calls & Messages'),
              content: const Text(
                  'To receive calls and messages reliably when the app is closed, please enable "Auto-start" or "Background Execution" for SajniRe in your phone settings.'),
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
                    try {
                      await getAutoStartPermission();
                    } catch (e) {
                      debugPrint("AutoStart permission Error: $e");
                    }
                  },
                ),
              ],
            );
          },
        );
      }
    } on PlatformException catch (e) {
      debugPrint("AutoStart Error: $e");
    } catch (e) {
      debugPrint("AutoStart Unknown Error: $e");
    }
  }
}
