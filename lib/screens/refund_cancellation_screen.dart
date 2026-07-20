import 'package:flutter/material.dart';

class RefundCancellationScreen extends StatelessWidget {
  const RefundCancellationScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text('Refund & Cancellation', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
        backgroundColor: Colors.white,
        iconTheme: const IconThemeData(color: Colors.black),
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Refund & Cancellation Policy', style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            Text('Last updated: July 2025', style: TextStyle(fontSize: 13, color: Colors.grey.shade600)),
            const SizedBox(height: 20),
            const Text(
              'At SajniRe, we are committed to providing a fair and transparent experience for all users. Please read this policy carefully before making any wallet recharges or using paid features.',
              style: TextStyle(fontSize: 15, height: 1.6),
            ),

            _buildSection('1. Wallet Recharges — Non-Refundable',
              'All wallet recharges made through SajniRe are final and non-refundable under normal circumstances.\n\n'
              '• Once coins are added to your SajniRe wallet, they cannot be converted back to cash or transferred to a bank account.\n'
              '• Coins have no monetary value outside the SajniRe platform.\n'
              '• This policy applies to all payment methods including PayU, PhonePe, GPay, Paytm, and Google Play.',
            ),

            _buildSection('2. Exception — Payment Deducted but Coins Not Credited',
              'If your payment was deducted from your bank account or payment app but coins were NOT credited to your SajniRe wallet, you are eligible for a resolution:\n\n'
              '• Contact us at sajnireofficial@gmail.com within 7 days of the transaction.\n'
              '• Share your Transaction ID, payment screenshot, and registered mobile number.\n'
              '• We will investigate within 3–5 business days.\n'
              '• If the payment is confirmed on our end, the coins will be credited to your wallet. If not, we will assist you in raising a dispute with your payment provider.',
            ),

            _buildSection('3. Call Charges',
              '• Calls are billed at ₹3 per minute for male users.\n'
              '• Deductions happen from the in-app coin wallet.\n'
              '• If a call drops within the first 60 seconds due to a verified technical fault on our server, you may contact support for a review.\n'
              '• Call quality issues caused by the user\'s own network or device are not eligible for refunds.',
            ),

            _buildSection('4. Chat Charges',
              '• The first 5 chat messages are free for new users.\n'
              '• Subsequent messages are charged at ₹0.50 (5 coins) per message.\n'
              '• Coins deducted for sent messages are non-refundable.',
            ),

            _buildSection('5. Expert Withdrawals & Cancellations',
              '• Expert earnings are credited to their expert wallet based on completed calls.\n'
              '• Withdrawal requests are subject to a minimum balance threshold and processing time of 3–7 business days.\n'
              '• SajniRe reserves the right to withhold or cancel earnings in cases of policy violations, fraudulent activity, or disputed calls.',
            ),

            _buildSection('6. Account Deletion & Remaining Balance',
              '• If you choose to delete your SajniRe account, any remaining coin balance in your wallet will be permanently forfeited.\n'
              '• We strongly recommend spending your balance before requesting account deletion.\n'
              '• Deleted accounts cannot be recovered.',
            ),

            _buildSection('7. Fraudulent Transactions',
              'If you believe an unauthorized transaction was made from your account:\n'
              '• Immediately contact us at sajnireofficial@gmail.com.\n'
              '• We will temporarily freeze your account during the investigation.\n'
              '• Decisions made after investigation are final.',
            ),

            _buildSection('8. How to Request Support',
              'To raise a refund request or dispute:\n\n'
              '• Email: sajnireofficial@gmail.com\n'
              '• Phone/WhatsApp: +91 8987108642\n'
              '• Address: Fathehpur, Bhagalpur, Bihar\n'
              '• Please include: Registered mobile number, Transaction ID, Date of transaction, Screenshot of payment confirmation.\n\n'
              'We aim to respond to all queries within 2 business days.',
            ),

            _buildSection('9. Changes to This Policy',
              'SajniRe reserves the right to modify this Refund & Cancellation Policy at any time. Changes will be communicated via the app. Continued use of the app after changes constitutes your acceptance.',
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
