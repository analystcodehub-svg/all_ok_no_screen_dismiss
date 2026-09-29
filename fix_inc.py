import sys

def fix_file(filepath):
    with open(filepath, 'r') as f:
        content = f.read()

    bad_str = """      ),
    ),
    );
  }"""
    good_str = """      ),
    );
    );
  }"""
    
    if bad_str in content:
        content = content.replace(bad_str, good_str)
        print("Fixed.")
            
    with open(filepath, 'w') as f:
        f.write(content)

fix_file("lib/screens/incoming_call_screen.dart")
