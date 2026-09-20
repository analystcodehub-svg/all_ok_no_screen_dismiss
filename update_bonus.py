import re

with open('lib/screens/male_dashboard_screen.dart', 'r') as f:
    content = f.read()

# Update 20 to 200 in the logic
content = content.replace("coinBalance += 20;", "coinBalance += 200;")
content = content.replace("'coinBalance': 20,", "'coinBalance': 200,")
content = content.replace("appState.setCoinBalance(20);", "appState.setCoinBalance(200);")

# Update popup text
old_popup = """                const Text(
                  'Welcome Bonus!',
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Color(0xFF0F172A)),
                ),
                const SizedBox(height: 12),
                const Text(
                  'You have received 20 Free Coins as a welcome gift. You can use these coins to start making calls right away!',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 15, color: Color(0xFF64748B), height: 1.5),
                ),"""

new_popup = """                const Text(
                  '₹20 Welcome Bonus!',
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Color(0xFF0F172A)),
                ),
                const SizedBox(height: 12),
                const Text(
                  'You have received ₹20 (200 Coins) as a welcome gift. You can use these coins to start making calls right away!',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 15, color: Color(0xFF64748B), height: 1.5),
                ),"""

content = content.replace(old_popup, new_popup)

with open('lib/screens/male_dashboard_screen.dart', 'w') as f:
    f.write(content)
