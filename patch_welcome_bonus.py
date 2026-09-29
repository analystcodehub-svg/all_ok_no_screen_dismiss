import re

file_path = "lib/screens/male_onboarding/male_onboarding_parent.dart"
with open(file_path, "r") as f:
    content = f.read()

replacement = """
      try {
        final docRef = FirebaseFirestore.instance.collection('users').doc(appState.uid);
        final docSnap = await docRef.get();
        
        // 100 coins = Rs 10 welcome bonus
        int finalBalance = 100; 
        if (docSnap.exists && docSnap.data() != null && docSnap.data()!.containsKey('coinBalance')) {
           finalBalance = (docSnap.data()!['coinBalance'] as num?)?.toInt() ?? 0;
        }

        await docRef.set({
          'mobileNumber': mobile,
          'nickname': nickname,
          'gender': 'male',
          'primaryLanguage': appState.primaryLanguage,
          'avatarIndex': appState.avatarIndex,
          'coinBalance': finalBalance,
          'hasUsedFreeCall': appState.hasUsedFreeCall,
        }, SetOptions(merge: true));
        
        if (mounted) {
           appState.setCoinBalance(finalBalance);
        }
"""

content = re.sub(
    r"try\s*\{\s*await FirebaseFirestore\.instance\.collection\('users'\)\.doc\(appState\.uid\)\.set\(\{.*?\}, SetOptions\(merge: true\)\);",
    replacement.strip(),
    content,
    flags=re.DOTALL
)

with open(file_path, "w") as f:
    f.write(content)

