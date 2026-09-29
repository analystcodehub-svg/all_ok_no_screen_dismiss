import sys

def fix_file(filepath):
    with open(filepath, 'r') as f:
        content = f.read()

    # The bad replacement was:
    bad_str = """      ),
    );
    );
  }"""
    
    good_str = """      ),
    ),
    );
  }"""
    
    if bad_str in content:
        content = content.replace(bad_str, good_str)
        print(f"Fixed {filepath}.")
            
    with open(filepath, 'w') as f:
        f.write(content)

fix_file("lib/screens/active_call_page.dart")
fix_file("lib/screens/incoming_call_screen.dart")
