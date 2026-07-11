import 'package:flutter/material.dart';

class PrivacyPolicyScreen extends StatelessWidget {
  const PrivacyPolicyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text('Privacy Policy', style: TextStyle(color: Colors.black)),
        backgroundColor: Colors.white,
        iconTheme: const IconThemeData(color: Colors.black),
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Privacy Policy', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
            SizedBox(height: 16),
            Text('Your privacy is important to us. This Privacy Policy explains how SajniRe collects, uses, and protects your personal information.', style: TextStyle(fontSize: 16)),
            SizedBox(height: 16),
            Text('1. Information Collection', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            SizedBox(height: 8),
            Text('We collect information you provide directly to us, such as when you create an account, update your profile, or communicate with experts. This includes your phone number, nickname, and usage data.', style: TextStyle(fontSize: 16)),
            SizedBox(height: 16),
            Text('2. Use of Information', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            SizedBox(height: 8),
            Text('The information we collect is used to facilitate matchmaking, process payments securely, and improve our services. We do not sell your personal data to third parties.', style: TextStyle(fontSize: 16)),
            SizedBox(height: 16),
            Text('3. Data Security', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            SizedBox(height: 8),
            Text('We implement appropriate security measures to protect your personal information against unauthorized access, alteration, disclosure, or destruction.', style: TextStyle(fontSize: 16)),
            SizedBox(height: 16),
            Text('4. Contact Us', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            SizedBox(height: 8),
            Text('If you have any questions or concerns about this Privacy Policy, please contact our support team through the app.', style: TextStyle(fontSize: 16)),
          ],
        ),
      ),
    );
  }
}
