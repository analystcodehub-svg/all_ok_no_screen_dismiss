import os
import re

# matchmaking_screen.dart
path = 'lib/screens/matchmaking_screen.dart'
with open(path, 'r') as f:
    content = f.read()
    
# Remove unnecessary null coalescing
content = content.replace("expertId: matchedExpertUid ?? '',", "expertId: matchedExpertUid,")
content = content.replace("receiverId: matchedExpertUid ?? '',", "receiverId: matchedExpertUid,")
content = content.replace("(matchedExpertUid ?? '').toUpperCase()", "matchedExpertUid.toUpperCase()")

# Fix withOpacity
content = content.replace('.withOpacity(', '.withValues(alpha: ')

# Fix use_build_context_synchronously
# Line 73
content = re.sub(r'Navigator\.pop\(context\);\n\s*return;', r'if (mounted) Navigator.pop(context);\n        return;', content)
# Line 119
content = re.sub(r'if \(!_isDisposed && mounted\) \{\n\s*await Future\.delayed\(const Duration\(seconds: 2\)\);\n\s*if \(mounted\) \{\n\s*Navigator\.pop\(context\);\n\s*\}\n\s*\}', r'if (!_isDisposed && mounted) {\n          await Future.delayed(const Duration(seconds: 2));\n          if (mounted) {\n            Navigator.pop(context);\n          }\n        }', content)

with open(path, 'w') as f:
    f.write(content)

# active_call_page.dart
path = 'lib/screens/active_call_page.dart'
with open(path, 'r') as f:
    content = f.read()

# Remove _markFreeCallUsed block
content = re.sub(r'  void _markFreeCallUsed\(\) async \{.*?\n  \}\n', '', content, flags=re.DOTALL)

with open(path, 'w') as f:
    f.write(content)

# Remove unnecessary foundation imports
for root, dirs, files in os.walk('.'):
    for file in files:
        if file.endswith('.dart'):
            filepath = os.path.join(root, file)
            with open(filepath, 'r') as f:
                content = f.read()
            if "import 'package:flutter/foundation.dart';\n" in content and "import 'package:flutter/material.dart';\n" in content:
                content = content.replace("import 'package:flutter/foundation.dart';\n", "")
                with open(filepath, 'w') as f:
                    f.write(content)

# Replace prints with debugPrint in test files
test_files = [
    'lib/test_db.dart', 'lib/test_firestore.dart', 'lib/test_fix_created.dart', 
    'lib/test_query.dart', 'test_get_experts.dart', 'test_swati.dart', 'test_payu.dart'
]
for file in test_files:
    if os.path.exists(file):
        with open(file, 'r') as f:
            content = f.read()
        if "debugPrint" not in content and "print(" in content:
            content = "import 'package:flutter/foundation.dart';\n" + content
        content = content.replace("print(", "debugPrint(")
        with open(file, 'w') as f:
            f.write(content)

