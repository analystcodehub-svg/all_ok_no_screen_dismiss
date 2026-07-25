import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../providers/app_state.dart';
import '../theme/app_theme.dart';
import 'gender_selection_screen.dart';
import 'main_navigation.dart';
import 'male_dashboard_screen.dart';

class OtpVerificationScreen extends StatefulWidget {
  final String verificationId;
  final String mobileNumber;

  const OtpVerificationScreen({
    super.key,
    required this.verificationId,
    required this.mobileNumber,
  });

  @override
  State<OtpVerificationScreen> createState() => _OtpVerificationScreenState();
}

class _OtpVerificationScreenState extends State<OtpVerificationScreen> {
  final TextEditingController _otpController = TextEditingController();
  bool _isLoading = false;

  @override
  void dispose() {
    _otpController.dispose();
    super.dispose();
  }

  void _verifyOtp() async {
    final otp = _otpController.text.trim();
    if (otp.length != 6) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a valid 6-digit OTP')),
      );
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      // Create a PhoneAuthCredential with the code
      PhoneAuthCredential credential = PhoneAuthProvider.credential(
        verificationId: widget.verificationId,
        smsCode: otp,
      );

      // Sign the user in (or link) with the credential
      UserCredential userCredential =
          await FirebaseAuth.instance.signInWithCredential(credential);

      if (userCredential.user != null) {
        // Successful login, check if user exists in Firestore
        final userDoc = await FirebaseFirestore.instance
            .collection('users')
            .doc(userCredential.user!.uid)
            .get();

        if (mounted) {
          if (userDoc.exists) {
            // Profile exists, load gender and route appropriately
            final data = userDoc.data() ?? {};
            final gender = (data['gender'] ?? 'male').toString();

            // Load app state
            final appState = context.read<AppState>();
            appState.setMobileNumber(widget.mobileNumber);
            appState.setSelectedGender(gender == 'male' ? 'Male' : 'Female');
            appState.setNickname((data['nickname'] ?? '').toString());
            
            // Navigate to Dashboard
            if (gender == 'male') {
              Navigator.pushAndRemoveUntil(
                context,
                MaterialPageRoute(builder: (context) => const MaleCallerDashboard()),
                (route) => false,
              );
            } else {
              Navigator.pushAndRemoveUntil(
                context,
                MaterialPageRoute(builder: (context) => const MainNavigation()),
                (route) => false,
              );
            }
          } else {
            // New user, navigate to Gender Selection to build profile
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(builder: (context) => const GenderSelectionScreen()),
            );
          }
        }
      }
    } on FirebaseAuthException catch (e) {
      if (mounted) {
        String message = 'Invalid OTP. Please try again.';
        if (e.code == 'invalid-verification-code') {
          message = 'The OTP you entered is incorrect.';
        } else if (e.code == 'session-expired') {
          message = 'The OTP has expired. Please request a new one.';
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(message)),
        );
      }
    } catch (e, stackTrace) {
      debugPrint("OTP Verification Error: $e");
      debugPrint("Stack Trace: $stackTrace");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('An error occurred: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Verify Phone'),
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: AppTheme.textBlack),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 20.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 20),
              const Text(
                'Enter OTP',
                style: TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.textBlack,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'We have sent a 6-digit code to +91 ${widget.mobileNumber}',
                style: const TextStyle(
                  fontSize: 16,
                  color: AppTheme.textGrey,
                ),
              ),
              const SizedBox(height: 40),
              // OTP Input Field
              Container(
                decoration: BoxDecoration(
                  color: AppTheme.inputBg,
                  borderRadius: BorderRadius.circular(15),
                  border: Border.all(
                    color: AppTheme.borderGrey,
                    width: 1.0,
                  ),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: TextField(
                  controller: _otpController,
                  keyboardType: TextInputType.number,
                  maxLength: 6,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 24,
                    letterSpacing: 12,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.textBlack,
                  ),
                  decoration: const InputDecoration(
                    counterText: "",
                    border: InputBorder.none,
                    hintText: "------",
                    hintStyle: TextStyle(
                      color: AppTheme.borderGrey,
                      letterSpacing: 12,
                    ),
                  ),
                  onChanged: (value) {
                    if (value.length == 6) {
                      _verifyOtp();
                    }
                  },
                ),
              ),
              const SizedBox(height: 40),
              ElevatedButton(
                onPressed: _isLoading ? null : _verifyOtp,
                child: _isLoading
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 2,
                        ),
                      )
                    : const Text('Verify & Continue'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
