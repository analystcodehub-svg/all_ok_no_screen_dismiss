import sys

with open("lib/screens/active_call_page.dart", 'r') as f:
    content = f.read()

target = """            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCallActionCircle"""

replacement = """            ],
          ),
        ),
      ),
      ),
    );
  }

  Widget _buildCallActionCircle"""

content = content.replace(target, replacement)
with open("lib/screens/active_call_page.dart", 'w') as f:
    f.write(content)

