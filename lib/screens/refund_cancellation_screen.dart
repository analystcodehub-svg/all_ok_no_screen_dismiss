import 'package:flutter/material.dart';

class RefundCancellationScreen extends StatelessWidget {
  const RefundCancellationScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text('Refund & Cancellation', style: TextStyle(color: Colors.black)),
        backgroundColor: Colors.white,
        iconTheme: const IconThemeData(color: Colors.black),
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Refund & Cancellation Policy', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
            SizedBox(height: 16),
            Text('At SajniRe, we strive to provide the best experience. Please read our policy regarding wallet recharges and call deductions.', style: TextStyle(fontSize: 16)),
            SizedBox(height: 16),
            Text('1. Wallet Recharges', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            SizedBox(height: 8),
            Text('All wallet recharges are final and non-refundable. Once money is added to your SajniRe wallet, it cannot be transferred back to your bank account or credit card.', style: TextStyle(fontSize: 16)),
            SizedBox(height: 16),
            Text('2. Call Deductions', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            SizedBox(height: 8),
            Text('Charges are deducted on a per-minute basis during your consultation. If a call drops due to technical issues on our end within the first 60 seconds, you may contact support for a dispute review.', style: TextStyle(fontSize: 16)),
            SizedBox(height: 16),
            Text('3. Dispute Resolution', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            SizedBox(height: 8),
            Text('Any disputes regarding deductions must be raised within 24 hours of the transaction. Our team will review the logs and, if deemed valid, credit the disputed amount back to your in-app wallet.', style: TextStyle(fontSize: 16)),
            SizedBox(height: 16),
            Text('4. Cancellation', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            SizedBox(height: 8),
            Text('You may cancel or delete your account at any time through the app settings. However, any unused wallet balance will be forfeited upon account deletion.', style: TextStyle(fontSize: 16)),
          ],
        ),
      ),
    );
  }
}
