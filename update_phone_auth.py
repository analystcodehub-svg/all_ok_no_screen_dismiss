import re

with open('lib/screens/phone_auth_screen.dart', 'r') as f:
    content = f.read()

# Add import for otp_verification_screen
content = content.replace("import 'male_dashboard_screen.dart';", "import 'male_dashboard_screen.dart';\nimport 'otp_verification_screen.dart';")

# Change controllers
content = re.sub(
    r"final TextEditingController _emailController = TextEditingController\(\);\n  final TextEditingController _passwordController = TextEditingController\(\);",
    "final TextEditingController _phoneController = TextEditingController();",
    content
)

# Fix dispose
content = re.sub(
    r"_emailController\.dispose\(\);\n    _passwordController\.dispose\(\);",
    "_phoneController.dispose();",
    content
)

# Update _onGetOtpPressed
new_otp_func = """  void _onGetOtpPressed() async {
    if (_isLoading) return;
    if (_formKey.currentState!.validate()) {
      final phone = _phoneController.text.trim();
      final phoneNumber = '+91$phone';
      
      setState(() {
        _isLoading = true;
      });

      try {
        await FirebaseAuth.instance.verifyPhoneNumber(
          phoneNumber: phoneNumber,
          verificationCompleted: (PhoneAuthCredential credential) async {
            // Auto-retrieval or Instant verification (usually on Android)
            try {
              await FirebaseAuth.instance.signInWithCredential(credential);
              // Handle routing in AuthWrapper or via another listener, 
              // but we'll let auth state changes handle it generally, 
              // or navigate manually if needed. For now, we'll let AuthWrapper catch the state change.
              if (mounted) {
                setState(() => _isLoading = false);
              }
            } catch (e) {
              if (mounted) {
                setState(() => _isLoading = false);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Auto-verification failed: $e')),
                );
              }
            }
          },
          verificationFailed: (FirebaseAuthException e) {
            if (mounted) {
              setState(() => _isLoading = false);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Verification failed: ${e.message}')),
              );
            }
          },
          codeSent: (String verificationId, int? resendToken) {
            if (mounted) {
              setState(() => _isLoading = false);
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => OtpVerificationScreen(
                    verificationId: verificationId,
                    mobileNumber: phone,
                  ),
                ),
              );
            }
          },
          codeAutoRetrievalTimeout: (String verificationId) {
            // Timeout handling if necessary
          },
          timeout: const Duration(seconds: 60),
        );
      } catch (e) {
        if (mounted) {
          setState(() {
            _isLoading = false;
          });
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error: $e')),
          );
        }
      }
    }
  }"""

content = re.sub(
    r"void _onGetOtpPressed\(\) async \{.*?\n  \}",
    new_otp_func,
    content,
    flags=re.DOTALL
)

# Replace commented phone field and email/pass fields with just Phone field
phone_field_replacement = """// Phone Number Field
                            Container(
                              decoration: BoxDecoration(
                                color: AppTheme.inputBg,
                                borderRadius: BorderRadius.circular(15),
                                border: Border.all(
                                  color: AppTheme.borderGrey,
                                  width: 1.0,
                                ),
                              ),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                              ),
                              child: Row(
                                children: [
                                  // Country Prefix +91 Dropdown
                                  Row(
                                    children: [
                                      Image.network(
                                        'https://flagcdn.com/w40/in.png',
                                        width: 24,
                                        errorBuilder:
                                            (context, error, stackTrace) =>
                                                const Icon(
                                                  Icons.flag,
                                                  size: 24,
                                                ),
                                      ),
                                      const SizedBox(width: 8),
                                      const Text(
                                        '+91',
                                        style: TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.bold,
                                          color: AppTheme.textBlack,
                                        ),
                                      ),
                                      const Icon(
                                        Icons.keyboard_arrow_down,
                                        color: AppTheme.textGrey,
                                        size: 18,
                                      ),
                                    ],
                                  ),
                                  const SizedBox(width: 12),
                                  Container(
                                    height: 24,
                                    width: 1,
                                    color: AppTheme.borderGrey,
                                  ),
                                  const SizedBox(width: 12),
                                  // Mobile input
                                  Expanded(
                                    child: TextFormField(
                                      controller: _phoneController,
                                      keyboardType: TextInputType.phone,
                                      style: const TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w600,
                                        color: AppTheme.textBlack,
                                      ),
                                      decoration: const InputDecoration(
                                        hintText: 'Your Mobile Number',
                                        hintStyle: TextStyle(
                                          color: AppTheme.textGrey,
                                          fontWeight: FontWeight.normal,
                                        ),
                                        filled: false,
                                        border: InputBorder.none,
                                        enabledBorder: InputBorder.none,
                                        focusedBorder: InputBorder.none,
                                        contentPadding: EdgeInsets.zero,
                                      ),
                                      validator: (value) {
                                        if (value == null || value.isEmpty) {
                                          return 'Please enter mobile number';
                                        }
                                        if (value.length < 10) {
                                          return 'Please enter a valid 10-digit number';
                                        }
                                        return null;
                                      },
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 16),"""

content = re.sub(
    r"// Phone Number Field\s*/\*.*?\*/\s*// Email Field.*?// Password Field.*?(?=\s*// Optional Referral Code Field)",
    phone_field_replacement,
    content,
    flags=re.DOTALL
)

# Change Login button text to Get OTP
content = content.replace("const Text('Login')", "const Text('Get OTP')")

with open('lib/screens/phone_auth_screen.dart', 'w') as f:
    f.write(content)
