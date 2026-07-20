import 'package:flutter/material.dart';

class PrivacyPolicyScreen extends StatelessWidget {
  const PrivacyPolicyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text('Privacy Policy', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
        backgroundColor: Colors.white,
        iconTheme: const IconThemeData(color: Colors.black),
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Privacy Policy', style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            Text('Last updated: July 2025', style: TextStyle(fontSize: 13, color: Colors.grey.shade600)),
            const SizedBox(height: 20),
            const Text(
              'SajniRe ("we", "us", or "our") is committed to protecting your privacy. This Privacy Policy applies to all users of our mobile application — including male users (callers) and female experts — and explains how we collect, use, store, and share your personal information.',
              style: TextStyle(fontSize: 15, height: 1.6),
            ),

            _buildSection('1. Information We Collect',
              '• Phone Number: Used for account creation and login via OTP verification.\n'
              '• Nickname & Profile Data: Your chosen display name, gender, language preference, and avatar selected during onboarding.\n'
              '• Payment Data: Wallet recharge amount, transaction ID, and payment gateway used (PayU/Google Play). We do NOT store card numbers or UPI PINs.\n'
              '• Call & Chat Logs: Duration of calls, call timestamps, and chat message metadata (not the content of messages). Messages are temporarily routed via Firebase Realtime Database and are NOT permanently stored on our servers.\n'
              '• Microphone Usage: Required to enable live audio calling features. Audio is transmitted in real-time and NOT recorded or stored by us.\n'
              '• Device Information: Device model, OS version, and app version for troubleshooting and improving performance.\n'
              '• Usage Analytics: How you interact with the app (screens visited, buttons tapped) to improve user experience.',
            ),

            _buildSection('2. How We Use Your Information',
              '• To create and manage your account.\n'
              '• To facilitate live audio calls between male users and female experts.\n'
              '• To process in-app wallet recharges and deduct coins per call/chat usage.\n'
              '• To send push notifications for incoming calls and important app updates.\n'
              '• To detect and prevent fraud, abuse, or violations of our Terms & Conditions.\n'
              '• To respond to support requests and resolve disputes.\n'
              '• To comply with applicable Indian laws and regulations.',
            ),

            _buildSection('3. Data Sharing',
              'We do NOT sell or rent your personal data. We may share data only in these cases:\n\n'
              '• Payment Processors: PayU and Google Play receive transaction data necessary to process payments.\n'
              '• Firebase (Google): We use Firebase for authentication, real-time database, push notifications, and cloud storage.\n'
              '• Legal Compliance: We may disclose data if required by law, court order, or government authority.',
            ),

            _buildSection('4. Permissions Used',
              '• RECORD_AUDIO / Microphone: Required for live audio calls. Audio is not recorded by us.\n'
              '• INTERNET: Required for all app functionality.\n'
              '• POST_NOTIFICATIONS: To deliver incoming call and message notifications.\n'
              '• CAMERA (optional): For profile photo selection, if used.',
            ),

            _buildSection('5. Data Retention',
              '• Account data is retained as long as your account is active.\n'
              '• Call logs are stored for up to 90 days for dispute resolution purposes.\n'
              '• Chat messages are temporarily cached locally on your device and are NOT stored on our servers permanently.\n'
              '• On account deletion, all personal data is deleted within 30 days.',
            ),

            _buildSection('6. Children\'s Privacy',
              'SajniRe is strictly intended for users aged 18 years and above. We do not knowingly collect any personal data from minors. If we discover that a minor has registered, we will immediately delete their account and data.',
            ),

            _buildSection('7. User Rights',
              'You have the right to:\n'
              '• Access your personal data.\n'
              '• Request correction of inaccurate data.\n'
              '• Request deletion of your account and data.\n'
              '• Withdraw consent at any time by deleting the app or contacting us.\n\n'
              'To exercise these rights, contact us at: sajnireofficial@gmail.com',
            ),

            _buildSection('8. Security',
              'We implement industry-standard security measures including HTTPS encryption, Firebase Security Rules, and secure payment processing via PayU. However, no system is 100% secure. We urge you to keep your phone secure.',
            ),

            _buildSection('9. Changes to This Policy',
              'We may update this Privacy Policy from time to time. Significant changes will be notified via the app. Your continued use of the app after changes means you accept the updated policy.',
            ),

            _buildSection('10. Contact Us',
              'For any privacy-related questions or concerns:\n\n'
              '• Email: sajnireofficial@gmail.com\n'
              '• Phone/WhatsApp: +91 8987108642\n'
              '• Address: Fathehpur, Bhagalpur, Bihar',
            ),

            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  Widget _buildSection(String title, String content) {
    return Padding(
      padding: const EdgeInsets.only(top: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: Color(0xFF1E3A8A))),
          const SizedBox(height: 8),
          Text(content, style: const TextStyle(fontSize: 15, height: 1.6, color: Color(0xFF374151))),
        ],
      ),
    );
  }
}
