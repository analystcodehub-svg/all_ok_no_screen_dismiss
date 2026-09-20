import re

with open('lib/screens/male_dashboard_screen.dart', 'r') as f:
    content = f.read()

bad_block = """      } else {
        await FirebaseFirestore.instance.collection('users').doc(myUid).set({
          'uid': myUid,
          'coinBalance': 20, // Give 20 on creation too
          'welcomeBonusReceived': true,
          'hasUsedFreeCall': false,
          'createdAt': FieldValue.serverTimestamp(),
        });
        appState.setCoinBalance(20);
        
        if (mounted) {
          _showWelcomeBonusPopup();
        }
      }
          'freeMessagesUsed': 0,
          'gender': 'male',
        }, SetOptions(merge: true));
        appState.setCoinBalance(0);
        appState.setHasUsedFreeCall(false);
        appState.setFreeMessagesUsed(0);
      }"""

good_block = """      } else {
        await FirebaseFirestore.instance.collection('users').doc(myUid).set({
          'uid': myUid,
          'coinBalance': 20,
          'welcomeBonusReceived': true,
          'hasUsedFreeCall': false,
          'createdAt': FieldValue.serverTimestamp(),
          'freeMessagesUsed': 0,
          'gender': 'male',
        }, SetOptions(merge: true));
        appState.setCoinBalance(20);
        appState.setHasUsedFreeCall(false);
        appState.setFreeMessagesUsed(0);
        
        if (mounted) {
          _showWelcomeBonusPopup();
        }
      }"""

content = content.replace(bad_block, good_block)

with open('lib/screens/male_dashboard_screen.dart', 'w') as f:
    f.write(content)
