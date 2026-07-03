import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:provider/provider.dart';
import '../theme/app_colors.dart';
import '../providers/app_state.dart';
import 'kyc_pan_screen.dart';

class WithdrawScreen extends StatefulWidget {
  final double amount;

  const WithdrawScreen({super.key, required this.amount});

  @override
  State<WithdrawScreen> createState() => _WithdrawScreenState();
}

class _WithdrawScreenState extends State<WithdrawScreen> {
  final _upiCtrl = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _isLoading = false;
  bool _agreedToTds = false;

  @override
  void dispose() {
    _upiCtrl.dispose();
    super.dispose();
  }

  double get _tdsAmount => widget.amount * 0.30;
  double get _receivableAmount => widget.amount - _tdsAmount;

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (!_agreedToTds) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Please acknowledge the TDS deduction to proceed.'),
        backgroundColor: Colors.orange,
      ));
      return;
    }

    setState(() => _isLoading = true);
    try {
      final expertId = context.read<AppState>().uid;
      await FirebaseFirestore.instance.collection('withdrawal_requests').add({
        'expertId': expertId,
        'amount': widget.amount,
        'tdsDeducted': _tdsAmount,
        'receivableAmount': _receivableAmount,
        'upiId': _upiCtrl.text.trim(),
        'status': 'pending',
        'kycCompleted': false,
        'requestedAt': FieldValue.serverTimestamp(),
      });

      // Reset balance
      await FirebaseFirestore.instance
          .collection('experts')
          .doc(expertId)
          .update({'redeemableBalance': 0.0});

      if (!mounted) return;
      Navigator.pop(context, true); // signal success
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Withdrawal request submitted! (30% TDS will be deducted)'),
        backgroundColor: AppColors.successGreen,
      ));
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgLight,
      appBar: AppBar(
        title: const Text('Withdraw Earnings',
            style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
        backgroundColor: AppColors.primaryBlue,
        iconTheme: const IconThemeData(color: Colors.white),
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // KYC Incomplete Banner
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.orange.shade50,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.orange.shade300, width: 1.5),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.warning_amber_rounded,
                            color: Colors.orange.shade700, size: 22),
                        const SizedBox(width: 8),
                        Text(
                          'KYC Not Completed',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                            color: Colors.orange.shade800,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Your KYC verification is pending. Without KYC, 30% TDS will be deducted from your withdrawal as per Indian Income Tax regulations.',
                      style: TextStyle(
                        fontSize: 13,
                        color: AppColors.textGrey,
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: 12),
                    GestureDetector(
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const KycPanScreen()),
                      ),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 10),
                        decoration: BoxDecoration(
                          color: Colors.orange.shade600,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.verified_user_rounded,
                                color: Colors.white, size: 16),
                            SizedBox(width: 8),
                            Text(
                              'Complete KYC to avoid TDS',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              // Withdrawal Breakdown Card
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                        color: Colors.black.withOpacity(0.04),
                        blurRadius: 10,
                        offset: const Offset(0, 3)),
                  ],
                ),
                child: Column(
                  children: [
                    _buildBreakdownRow('Withdrawal Amount',
                        '₹${widget.amount.toStringAsFixed(2)}', Colors.black87),
                    const Divider(height: 20),
                    _buildBreakdownRow(
                        '30% TDS Deduction',
                        '- ₹${_tdsAmount.toStringAsFixed(2)}',
                        Colors.red.shade600),
                    const Divider(height: 20),
                    _buildBreakdownRow(
                        'You Will Receive',
                        '₹${_receivableAmount.toStringAsFixed(2)}',
                        AppColors.successGreen,
                        isBold: true),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              // UPI ID Field
              const Text(
                'UPI ID',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textDark,
                ),
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _upiCtrl,
                keyboardType: TextInputType.emailAddress,
                decoration: InputDecoration(
                  hintText: 'e.g. yourname@upi or 9876543210@paytm',
                  hintStyle:
                      const TextStyle(color: AppColors.textGrey, fontSize: 13),
                  prefixIcon: const Icon(Icons.account_balance_wallet_outlined,
                      color: AppColors.primaryBlue, size: 20),
                  filled: true,
                  fillColor: Colors.white,
                  contentPadding: const EdgeInsets.symmetric(
                      vertical: 14, horizontal: 16),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: Colors.grey.shade200)),
                  enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: Colors.grey.shade200)),
                  focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(
                          color: AppColors.primaryBlue, width: 1.5)),
                  errorBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: Colors.red)),
                ),
                validator: (v) {
                  if (v == null || v.trim().isEmpty) {
                    return 'Please enter your UPI ID';
                  }
                  if (!v.contains('@')) {
                    return 'Invalid UPI ID format (e.g. name@upi)';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 20),

              // TDS Acknowledgement checkbox
              GestureDetector(
                onTap: () => setState(() => _agreedToTds = !_agreedToTds),
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: _agreedToTds
                          ? AppColors.primaryBlue
                          : Colors.grey.shade300,
                    ),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        width: 22,
                        height: 22,
                        decoration: BoxDecoration(
                          color: _agreedToTds
                              ? AppColors.primaryBlue
                              : Colors.white,
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                            color: _agreedToTds
                                ? AppColors.primaryBlue
                                : Colors.grey.shade400,
                          ),
                        ),
                        child: _agreedToTds
                            ? const Icon(Icons.check,
                                color: Colors.white, size: 14)
                            : null,
                      ),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Text(
                          'I understand that 30% TDS will be deducted from my withdrawal amount as per Indian Income Tax Act, Section 194C, since my KYC is not completed.',
                          style: TextStyle(
                            fontSize: 12,
                            color: AppColors.textGrey,
                            height: 1.4,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 28),

              // Submit Button
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  onPressed: _isLoading ? null : _submit,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primaryBlue,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                  ),
                  child: _isLoading
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                              color: Colors.white, strokeWidth: 2),
                        )
                      : Text(
                          'Withdraw ₹${_receivableAmount.toStringAsFixed(0)} (after TDS)',
                          style: const TextStyle(
                              fontSize: 15, fontWeight: FontWeight.bold),
                        ),
                ),
              ),
              const SizedBox(height: 16),
              const Center(
                child: Text(
                  'Transfer takes 3–5 business days',
                  style: TextStyle(fontSize: 12, color: AppColors.textGrey),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBreakdownRow(String label, String value, Color valueColor,
      {bool isBold = false}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label,
            style: TextStyle(
              fontSize: 13,
              color: isBold ? AppColors.textDark : AppColors.textGrey,
              fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
            )),
        Text(value,
            style: TextStyle(
              fontSize: isBold ? 16 : 14,
              fontWeight: FontWeight.bold,
              color: valueColor,
            )),
      ],
    );
  }
}
