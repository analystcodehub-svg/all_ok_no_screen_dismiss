import re

# 1. Undo the hack in male_onboarding_parent.dart
file_path = "lib/screens/male_onboarding/male_onboarding_parent.dart"
with open(file_path, "r") as f:
    content = f.read()

replacement = """
      try {
        await FirebaseFirestore.instance.collection('users').doc(appState.uid).set({
          'mobileNumber': mobile,
          'nickname': nickname,
          'gender': 'male',
          'primaryLanguage': appState.primaryLanguage,
          'avatarIndex': appState.avatarIndex,
          'coinBalance': appState.coinBalance,
          'hasUsedFreeCall': appState.hasUsedFreeCall,
        }, SetOptions(merge: true));
"""

# The hack looks like:
#      try {
#        final docRef = FirebaseFirestore.instance.collection('users').doc(appState.uid);
# ...
#        if (mounted) {
#           appState.setCoinBalance(finalBalance);
#        }

content = re.sub(
    r"try\s*\{\s*final docRef = FirebaseFirestore.*?appState\.setCoinBalance\(finalBalance\);\s*\}",
    replacement.strip(),
    content,
    flags=re.DOTALL
)

with open(file_path, "w") as f:
    f.write(content)


# 2. Fix male_dashboard_screen.dart (change 200 to 100)
file_path2 = "lib/screens/male_dashboard_screen.dart"
with open(file_path2, "r") as f:
    content2 = f.read()

content2 = content2.replace("coinBalance += 200;", "coinBalance += 100;")
content2 = content2.replace("'coinBalance': 200,", "'coinBalance': 100,")
content2 = content2.replace("appState.setCoinBalance(200);", "appState.setCoinBalance(100);")

with open(file_path2, "w") as f:
    f.write(content2)

