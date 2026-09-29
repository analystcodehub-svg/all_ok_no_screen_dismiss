import sys

def patch_file(filepath):
    with open(filepath, 'r') as f:
        content = f.read()
    
    old_logic = """      int actualDuration = localDuration;
      if (logDoc != null && logDoc.exists) {
        final data = logDoc.data()!;
        final callerDuration = (data['durationSeconds'] as num?)?.toInt() ?? 0;
        // Use the caller's duration if it's smaller, to give the exact figure
        if (callerDuration < actualDuration) {
          actualDuration = callerDuration;
        }
      }"""

    new_logic = """      int actualDuration = localDuration;
      if (logDoc != null && logDoc.exists) {
        final data = logDoc.data()!;
        final callerDuration = (data['durationSeconds'] as num?)?.toInt() ?? 0;
        // Use the caller's duration if it's smaller, to give the exact figure
        if (callerDuration < actualDuration) {
          actualDuration = callerDuration;
        }
      } else {
        // CRITICAL FIX: If the caller never logged the call (e.g. app crashed or force closed),
        // we CANNOT trust the female's local duration because it could be a ghost call.
        // We must default to 0 earnings to prevent the exploit.
        debugPrint('Caller did not log the call (logDoc missing). Forcing actualDuration to 0 to prevent ghost earning.');
        actualDuration = 0;
      }"""

    if old_logic in content:
        content = content.replace(old_logic, new_logic)
        with open(filepath, 'w') as f:
            f.write(content)
        print("Fixed actualDuration logic!")
    else:
        print("Could not find old logic!")

fix_file("lib/screens/active_call_page.dart")
