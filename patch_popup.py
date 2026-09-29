import re

file_path = "lib/screens/male_dashboard_screen.dart"
with open(file_path, "r") as f:
    content = f.read()

content = content.replace("'₹20 Welcome Bonus!',", "'₹10 Welcome Bonus!',")
content = content.replace("'You have received ₹20 (200 Coins) as a welcome gift. You can use these coins to start making calls right away!',", "'You have received ₹10 (100 Coins) as a welcome gift. You can use these coins to start making calls right away!',")

with open(file_path, "w") as f:
    f.write(content)

