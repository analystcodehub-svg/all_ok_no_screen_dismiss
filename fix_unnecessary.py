import os
test_files = [
    'lib/test_db.dart', 'lib/test_firestore.dart', 'lib/test_fix_created.dart', 
    'lib/test_query.dart'
]
for file in test_files:
    if os.path.exists(file):
        with open(file, 'r') as f:
            content = f.read()
        content = content.replace("import 'package:flutter/foundation.dart';\n", "")
        with open(file, 'w') as f:
            f.write(content)
