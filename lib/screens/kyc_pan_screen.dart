import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import 'kyc_bank_details_screen.dart';

class KycPanScreen extends StatefulWidget {
  const KycPanScreen({super.key});

  @override
  State<KycPanScreen> createState() => _KycPanScreenState();
}

class _KycPanScreenState extends State<KycPanScreen> {
  final _formKey = GlobalKey<FormState>();
  final _panNameCtrl = TextEditingController();
  final _panNumberCtrl = TextEditingController();

  @override
  void dispose() {
    _panNameCtrl.dispose();
    _panNumberCtrl.dispose();
    super.dispose();
  }

  void _proceed() {
    if (!_formKey.currentState!.validate()) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => KycBankDetailsScreen(
          panName: _panNameCtrl.text.trim(),
          panNumber: _panNumberCtrl.text.trim().toUpperCase(),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgLight,
      appBar: AppBar(
        title: const Text(
          'KYC Verification',
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
            // Step indicator
            _buildStepIndicator(),
            const SizedBox(height: 28),

            // Hero Banner
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [AppColors.gradientBlueStart, AppColors.gradientBlueEnd],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(18),
              ),
              child: const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.verified_user_rounded,
                          color: Colors.white, size: 26),
                      SizedBox(width: 10),
                      Text(
                        'PAN Card Verification',
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: 8),
                  Text(
                    'To enable withdrawals, we need to verify your identity using your PAN card as per Indian regulations.',
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.white,
                      height: 1.45,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 28),

            // Form Card
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(18),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.04),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Enter PAN Card Details',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: AppColors.textDark,
                      ),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'Details must match your PAN card exactly.',
                      style: TextStyle(
                        fontSize: 12,
                        color: AppColors.textGrey,
                      ),
                    ),
                    const SizedBox(height: 24),

                    // Full Name on PAN
                    _buildLabel('Full Name (as on PAN card)'),
                    const SizedBox(height: 8),
                    _buildTextField(
                      controller: _panNameCtrl,
                      hint: 'e.g. RAHUL SHARMA',
                      icon: Icons.person_outline_rounded,
                      textCapitalization: TextCapitalization.characters,
                      validator: (v) {
                        if (v == null || v.trim().isEmpty) return 'Required';
                        if (v.trim().length < 3) return 'Enter full name';
                        return null;
                      },
                    ),
                    const SizedBox(height: 20),

                    // PAN Number
                    _buildLabel('PAN Card Number'),
                    const SizedBox(height: 8),
                    _buildTextField(
                      controller: _panNumberCtrl,
                      hint: 'e.g. ABCDE1234F',
                      icon: Icons.credit_card_rounded,
                      textCapitalization: TextCapitalization.characters,
                      maxLength: 10,
                      validator: (v) {
                        if (v == null || v.trim().isEmpty) return 'Required';
                        final panRegex = RegExp(r'^[A-Z]{5}[0-9]{4}[A-Z]{1}$');
                        if (!panRegex.hasMatch(v.trim().toUpperCase())) {
                          return 'Invalid PAN format (e.g. ABCDE1234F)';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 8),

                    // Notice
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.amber.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                            color: Colors.amber.shade300, width: 1),
                      ),
                      child: const Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(Icons.lock_outline,
                              size: 16, color: Colors.amber),
                          SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Your data is encrypted and used only for KYC verification per RBI guidelines.',
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
                    const SizedBox(height: 24),

                    SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: ElevatedButton(
                        onPressed: _proceed,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primaryBlue,
                          foregroundColor: Colors.white,
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        child: const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              'Continue to Bank Details',
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            SizedBox(width: 8),
                            Icon(Icons.arrow_forward_rounded, size: 18),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
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
        _buildStep(1, 'PAN Card', true, false),
        Expanded(
          child: Container(height: 2, color: Colors.grey.shade300),
        ),
        _buildStep(2, 'Bank Details', false, false),
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
    int? maxLength,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      textCapitalization: textCapitalization,
      maxLength: maxLength,
      validator: validator,
      decoration: InputDecoration(
        hintText: hint,
        counterText: '',
        hintStyle: const TextStyle(color: AppColors.textGrey, fontSize: 14),
        prefixIcon: Icon(icon, color: AppColors.primaryBlue, size: 20),
        filled: true,
        fillColor: AppColors.bgLight,
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
