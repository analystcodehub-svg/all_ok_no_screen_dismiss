import re

file_path = "lib/utils/permission_helper.dart"
with open(file_path, "r") as f:
    content = f.read()

replacement = """
  static Future<void> checkAndRequestNotificationPermission(BuildContext context) async {
    final status = await Permission.notification.status;
    
    if (!status.isGranted) {
      final newStatus = await Permission.notification.request();
      if (newStatus.isPermanentlyDenied) {
        // openAppSettings();
      }
    }
  }
"""

content = re.sub(
    r"static Future<void> checkAndRequestNotificationPermission\(BuildContext context\) async \{.*?\s*\}\s*\}",
    replacement.strip(),
    content,
    flags=re.DOTALL
)

with open(file_path, "w") as f:
    f.write(content)

