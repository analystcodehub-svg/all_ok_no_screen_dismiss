import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:provider/provider.dart';
import '../theme/app_colors.dart';
import '../providers/app_state.dart';
import 'kyc_success_screen.dart';

class KycBankDetailsScreen extends StatefulWidget {
  final String panName;
  final String panNumber;

  const KycBankDetailsScreen({
    super.key,
    required this.panName,
    required this.panNumber,
  });

  @override
  State<KycBankDetailsScreen> createState() => _KycBankDetailsScreenState();
}

class _KycBankDetailsScreenState extends State<KycBankDetailsScreen> {
  final _formKey = GlobalKey<FormState>();
  final _accountHolderCtrl = TextEditingController();
  final _accountNumberCtrl = TextEditingController();
  final _confirmAccountCtrl = TextEditingController();
  final _ifscCtrl = TextEditingController();
  final _bankNameCtrl = TextEditingController();
  bool _isLoading = false;

  @override
  void dispose() {
    _accountHolderCtrl.dispose();
    _accountNumberCtrl.dispose();
    _confirmAccountCtrl.dispose();
    _ifscCtrl.dispose();
    _bankNameCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_accountNumberCtrl.text != _confirmAccountCtrl.text) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Account numbers do not match.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() => _isLoading = true);
    try {
      final nickname = context.read<AppState>().uid;
      await FirebaseFirestore.instance.collection('kyc_requests').add({
        'expertId': nickname,
        'panName': widget.panName,
        'panNumber': widget.panNumber.toUpperCase(),
        'accountHolder': _accountHolderCtrl.text.trim(),
        'accountNumber': _accountNumberCtrl.text.trim(),
        'ifscCode': _ifscCtrl.text.trim().toUpperCase(),
        'bankName': _bankNameCtrl.text.trim(),
        'status': 'pending',
        'submittedAt': FieldValue.serverTimestamp(),
      });

      if (!mounted) return;
      // Navigate to success screen, replacing current route
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const KycSuccessScreen()),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgLight,
      appBar: AppBar(
        title: const Text(
          'Bank Details',
          style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
        ),
        backgroundColor: AppColors.primaryBlue,
        iconTheme: const IconThemeData(color: Colors.white),
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Step Indicator
            _buildStepIndicator(),
            const SizedBox(height: 24),

            // Info card
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.lightBlueBg,
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Row(
                children: [
                  Icon(Icons.info_outline, color: AppColors.primaryBlue, size: 20),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Your bank account must match the name on your PAN card.',
                      style: TextStyle(
                        fontSize: 13,
                        color: AppColors.primaryBlue,
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // Form
            Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildLabel('Account Holder Name'),
                  const SizedBox(height: 8),
                  _buildTextField(
                    controller: _accountHolderCtrl,
                    hint: 'As per bank records',
                    icon: Icons.person_outline,
                    validator: (v) =>
                        v == null || v.trim().isEmpty ? 'Required' : null,
                  ),
                  const SizedBox(height: 20),

                  _buildLabel('Bank Name'),
                  const SizedBox(height: 8),
                  _buildTextField(
                    controller: _bankNameCtrl,
                    hint: 'e.g. State Bank of India',
                    icon: Icons.account_balance_outlined,
                    validator: (v) =>
                        v == null || v.trim().isEmpty ? 'Required' : null,
                  ),
                  const SizedBox(height: 20),

                  _buildLabel('Account Number'),
                  const SizedBox(height: 8),
                  _buildTextField(
                    controller: _accountNumberCtrl,
                    hint: 'Enter account number',
                    icon: Icons.credit_card_outlined,
                    keyboardType: TextInputType.number,
                    obscureText: false,
                    validator: (v) {
                      if (v == null || v.trim().isEmpty) return 'Required';
                      if (v.trim().length < 9) return 'Invalid account number';
                      return null;
                    },
                  ),
                  const SizedBox(height: 20),

                  _buildLabel('Confirm Account Number'),
                  const SizedBox(height: 8),
                  _buildTextField(
                    controller: _confirmAccountCtrl,
                    hint: 'Re-enter account number',
                    icon: Icons.credit_card,
                    keyboardType: TextInputType.number,
                    validator: (v) =>
                        v == null || v.trim().isEmpty ? 'Required' : null,
                  ),
                  const SizedBox(height: 20),

                  _buildLabel('IFSC Code'),
                  const SizedBox(height: 8),
                  _buildTextField(
                    controller: _ifscCtrl,
                    hint: 'e.g. SBIN0001234',
                    icon: Icons.code_outlined,
                    textCapitalization: TextCapitalization.characters,
                    validator: (v) {
                      if (v == null || v.trim().isEmpty) return 'Required';
                      final regex = RegExp(r'^[A-Z]{4}0[A-Z0-9]{6}$');
                      if (!regex.hasMatch(v.trim().toUpperCase())) {
                        return 'Invalid IFSC code (e.g. SBIN0001234)';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 36),

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
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      child: _isLoading
                          ? const SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(
                                color: Colors.white,
                                strokeWidth: 2,
                              ),
                            )
                          : const Text(
                              'Submit KYC',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                    ),
                  ),
                  const SizedBox(height: 20),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStepIndicator() {
    return Row(
      children: [
        _buildStep(1, 'PAN Card', true, true),
        Expanded(
          child: Container(height: 2, color: AppColors.primaryBlue),
        ),
        _buildStep(2, 'Bank Details', true, false),
      ],
    );
  }

  Widget _buildStep(int number, String label, bool isActive, bool isCompleted) {
    return Column(
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: isCompleted
                ? AppColors.successGreen
                : isActive
                    ? AppColors.primaryBlue
                    : Colors.grey.shade300,
            shape: BoxShape.circle,
          ),
          child: Center(
            child: isCompleted
                ? const Icon(Icons.check, color: Colors.white, size: 18)
                : Text(
                    '$number',
                    style: TextStyle(
                      color: isActive ? Colors.white : AppColors.textGrey,
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: isActive ? AppColors.primaryBlue : AppColors.textGrey,
          ),
        ),
      ],
    );
  }

  Widget _buildLabel(String text) {
    return Text(
      text,
      style: const TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w600,
        color: AppColors.textDark,
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String hint,
    required IconData icon,
    TextInputType keyboardType = TextInputType.text,
    TextCapitalization textCapitalization = TextCapitalization.none,
    bool obscureText = false,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      textCapitalization: textCapitalization,
      obscureText: obscureText,
      validator: validator,
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: AppColors.textGrey, fontSize: 14),
        prefixIcon: Icon(icon, color: AppColors.primaryBlue, size: 20),
        filled: true,
        fillColor: Colors.white,
        contentPadding:
            const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.grey.shade200),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.grey.shade200),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide:
              const BorderSide(color: AppColors.primaryBlue, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Colors.red),
        ),
      ),
    );
  }
}
