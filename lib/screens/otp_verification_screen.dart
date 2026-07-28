import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../providers/app_state.dart';
import '../theme/app_theme.dart';
import 'gender_selection_screen.dart';
import 'main_navigation.dart';
import 'male_dashboard_screen.dart';
import 'dart:async';

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
  late StreamSubscription<User?> _authSubscription;

  @override
  void initState() {
    super.initState();
    // Listen for automatic background login (Android Auto-retrieval)
    _authSubscription = FirebaseAuth.instance.authStateChanges().listen((User? user) async {
      if (user != null && mounted) {
        // User was automatically logged in by Firebase in the background
        
        // 1. Visibly fill the OTP code if it was caught by PhoneAuthScreen
        final autoCode = context.read<AppState>().autoRetrievedSmsCode;
        if (autoCode != null && autoCode.isNotEmpty) {
          _otpController.text = autoCode;
          context.read<AppState>().setAutoRetrievedSmsCode(null);
        }

        // 2. Wait for AuthWrapper (root) to finish loading user from Firestore
        // We replicate the wait here so we don't pop while it's still loading
        try {
          await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
        } catch (_) {}

        // 3. Add a small delay so the user can actually see the filled OTP magically!
        await Future.delayed(const Duration(milliseconds: 1500));

        if (mounted) {
          // 4. Pop to root. Because AuthWrapper has already swapped PhoneAuthScreen 
          // with GenderSelectionScreen, this reveals the new screen seamlessly!
          Navigator.of(context).popUntil((route) => route.isFirst);
        }
      }
    });
  }

  @override
  void dispose() {
    _authSubscription.cancel();
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
        // If the session expired BUT the user is actually logged in (due to auto-retrieval)
        if (e.code == 'session-expired' && FirebaseAuth.instance.currentUser != null) {
          // Do nothing, let the auth state listener pop the screen automatically
          return;
        }

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
