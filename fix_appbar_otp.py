import re

with open('lib/screens/otp_verification_screen.dart', 'r') as f:
    content = f.read()

replacement = """  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.black,
        elevation: 0,
        toolbarHeight: 0,
        systemOverlayStyle: const SystemUiOverlayStyle(
          statusBarColor: Colors.black,
          statusBarIconBrightness: Brightness.light,
          statusBarBrightness: Brightness.dark,
        ),
      ),
      body: Stack("""

content = content.replace("""  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Stack(""", replacement)

with open('lib/screens/otp_verification_screen.dart', 'w') as f:
    f.write(content)

with open('lib/screens/phone_auth_screen.dart', 'r') as f:
    content2 = f.read()
    
content2 = content2.replace("""  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(""", """  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.black,
        elevation: 0,
        toolbarHeight: 0,
        systemOverlayStyle: const SystemUiOverlayStyle(
          statusBarColor: Colors.black,
          statusBarIconBrightness: Brightness.light,
          statusBarBrightness: Brightness.dark,
        ),
      ),
      body: SafeArea(""")

with open('lib/screens/phone_auth_screen.dart', 'w') as f:
    f.write(content2)
