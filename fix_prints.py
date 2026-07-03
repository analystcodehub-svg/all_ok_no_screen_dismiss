import os

files_to_fix = [
    'test_swati.dart',
    'test_payu.dart',
    'test_query.dart',
    'test_fix_created.dart',
    'test_db.dart',
    'test_firestore.dart',
    'test_get_experts.dart',
    'lib/check_experts.dart',
    'check_experts_online.dart',
    'lib/check_experts2.dart',
    'lib/delete_mock_experts.dart'
]

for filepath in files_to_fix:
    if os.path.exists(filepath):
        with open(filepath, 'r') as f:
            content = f.read()
        
        # Add import for debugPrint if not there
        if 'debugPrint' not in content:
            content = "import 'package:flutter/foundation.dart';\n" + content
            
        content = content.replace('print(', 'debugPrint(')
        
        with open(filepath, 'w') as f:
            f.write(content)

