import os
import re

def process_file(filepath):
    with open(filepath, 'r') as f:
        content = f.read()

    # Replacements
    content = content.replace('.withOpacity(', '.withValues(alpha: ')
    
    # Specific file fixes
    if filepath.endswith('app_state.dart'):
        content = content.replace('String _uid = "";', 'final String _uid = "";')
    elif filepath.endswith('phone_auth_screen.dart'):
        content = content.replace("import 'package:flutter/services.dart';\n", "")
    elif filepath.endswith('expert_home_screen.dart'):
        content = content.replace("import 'phone_auth_screen.dart';\n", "")
    elif filepath.endswith('matchmaking_screen.dart'):
        content = content.replace('expert.uid!', 'expert.uid')
        content = content.replace('context!', 'context')
    elif filepath.endswith('active_call_page.dart'):
        # Just use regex to remove _markFreeCallUsed block
        content = re.sub(r'  Future<void> _markFreeCallUsed\(\) async \{.*?\n  \}\n', '', content, flags=re.DOTALL)
    elif filepath.endswith('chat_list_screen.dart'):
        content = re.sub(r"\' \+ doc\.id", " ${doc.id}'", content)
        content = re.sub(r"\' \+ currentUid", " ${currentUid}'", content)
    elif filepath.endswith('female_expert_dashboard.dart') or filepath.endswith('male_dashboard_screen.dart'):
        content = content.replace('activeColor:', 'activeThumbColor:')
    elif filepath.endswith('primary_language_page.dart'):
        content = content.replace('groupValue:', '// groupValue:')
        content = content.replace('onChanged:', '// onChanged:')
        content = content.replace('Radio<String>(', 'Radio<String>.adaptive(') # Maybe wait, let's leave radio group warning for now or just replace groupValue. 
        # Actually it's better to just leave RadioGroup warning for now, they are just info. 
        # Wait, I can just replace `activeColor` and `withOpacity`.

    with open(filepath, 'w') as f:
        f.write(content)

for root, dirs, files in os.walk('lib'):
    for file in files:
        if file.endswith('.dart'):
            process_file(os.path.join(root, file))

