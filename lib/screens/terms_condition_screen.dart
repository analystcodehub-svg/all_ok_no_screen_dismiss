import 'package:flutter/material.dart';

class TermsConditionScreen extends StatelessWidget {
  const TermsConditionScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text('Terms & Conditions', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
        backgroundColor: Colors.white,
        iconTheme: const IconThemeData(color: Colors.black),
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Terms & Conditions', style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            Text('Last updated: July 2025', style: TextStyle(fontSize: 13, color: Colors.grey.shade600)),
            const SizedBox(height: 20),
            const Text(
              'Welcome to SajniRe. These Terms & Conditions ("Terms") govern your use of the SajniRe mobile application. By registering or using this app, you agree to be legally bound by these Terms. If you do not agree, please do not use this app.',
              style: TextStyle(fontSize: 15, height: 1.6),
            ),

            _buildSection('1. Eligibility',
              '• You must be at least 18 years of age to use SajniRe.\n'
              '• By using the app, you confirm that you are 18 or older and have the legal capacity to enter into this agreement.\n'
              '• SajniRe reserves the right to terminate accounts if we find any user to be underage.',
            ),

            _buildSection('2. For Male Users (Callers)',
              '• Male users can browse female expert profiles and initiate audio calls or chat sessions.\n'
              '• Calls are charged at ₹4 per minute.\n'
              '• Chat messages are charged at ₹0.50 per message after the first 5 free messages.\n'
              '• Charges are deducted from your in-app coin wallet. You must maintain a sufficient balance to use paid services.\n'
              '• You agree NOT to:\n'
              '  — Use abusive, threatening, or sexually explicit language.\n'
              '  — Solicit personal contact information (phone numbers, social media) from experts.\n'
              '  — Record any call or conversation without consent.\n'
              '  — Attempt to communicate with experts outside the platform.',
            ),

            _buildSection('3. For Female Experts',
              '• Female experts must register, complete KYC/audio verification, and be approved before going live.\n'
              '• Experts earn a per-minute rate based on their assigned tier (Bronze or Silver).\n'
              '• Earnings are credited to your expert wallet and can be withdrawn upon request, subject to minimum withdrawal limits and verification.\n'
              '• Experts agree NOT to:\n'
              '  — Share personal contact information with callers.\n'
              '  — Engage in or encourage illegal activities.\n'
              '  — Provide false or misleading information during verification.\n'
              '• SajniRe reserves the right to suspend or permanently ban expert accounts for violations.',
            ),

            _buildSection('4. Wallet & Payments',
              '• In-app coins are purchased via the wallet recharge feature using Google Play.\n'
              '• 1 Rupee = 10 Coins. Coins can only be used within the SajniRe app.\n'
              '• Wallet balances are non-transferable and have no cash value outside the app.\n'
              '• We are not responsible for failed payments due to third-party payment gateway issues.',
            ),

            _buildSection('5. Prohibited Conduct',
              'The following are strictly prohibited on SajniRe:\n'
              '• Harassment, bullying, or intimidation of any user.\n'
              '• Sharing obscene, pornographic, or illegal content.\n'
              '• Creating fake accounts or impersonating others.\n'
              '• Using the app for any commercial solicitation or spam.\n'
              '• Attempting to hack, reverse engineer, or disrupt the platform.\n\n'
              'Violation of these rules will result in immediate account suspension and may be reported to law enforcement.',
            ),

            _buildSection('6. Intellectual Property',
              'All content, logos, designs, and software within SajniRe are the property of SajniRe and are protected by intellectual property laws. You may not copy, distribute, or create derivative works without our express written permission.',
            ),

            _buildSection('7. Limitation of Liability',
              'SajniRe is a platform that facilitates connections between users and experts. We are not responsible for:\n'
              '• The quality or accuracy of advice given by experts.\n'
              '• Any personal or financial loss resulting from interactions on the platform.\n'
              '• Technical issues beyond our control (network, device, third-party services).',
            ),

            _buildSection('8. Account Termination',
              '• You may delete your account at any time through the app settings.\n'
              '• We reserve the right to suspend or terminate accounts that violate these Terms without prior notice.\n'
              '• Unused coin balance is forfeited upon account deletion.',
            ),

            _buildSection('9. Governing Law',
              'These Terms are governed by the laws of India. Any disputes shall be subject to the exclusive jurisdiction of the courts located in India.',
            ),

            _buildSection('10. Changes to Terms',
              'We reserve the right to modify these Terms at any time. Changes will be communicated via the app. Continued use of the app after changes constitutes acceptance of the new Terms.',
            ),

            _buildSection('11. Contact Us',
              'For any questions about these Terms:\n\n'
              'Email: sajnireofficial@gmail.com\n'
              'Phone/WhatsApp: +91 8987108642\n'
              'Address: Fathehpur, Bhagalpur, Bihar',
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
