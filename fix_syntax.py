import sys

def fix_file(filepath):
    with open(filepath, 'r') as f:
        content = f.read()

    # Find the end of the build method (the last `);` before the next method)
    # The pattern in both files is likely:
    #       ),
    #     ),
    #   );
    # }
    
    # Actually, a simpler way is to just replace:
    old_str = """      ),
    );
  }"""
    
    new_str = """      ),
    );
    );
  }"""
    
    # Check if that exactly matches.
    if old_str in content:
        content = content.replace(old_str, new_str)
        print(f"Fixed {filepath} using standard pattern.")
    else:
        # Try a more lenient pattern
        print(f"Warning: standard pattern not found in {filepath}. Trying another...")
        old_str_2 = """        ),
      ),
    );
  }"""
        new_str_2 = """        ),
      ),
    );
    );
  }"""
        if old_str_2 in content:
            content = content.replace(old_str_2, new_str_2)
            print(f"Fixed {filepath} using pattern 2.")
            
    with open(filepath, 'w') as f:
        f.write(content)

fix_file("lib/screens/active_call_page.dart")
fix_file("lib/screens/incoming_call_screen.dart")
