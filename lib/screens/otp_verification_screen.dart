import "package:flutter/services.dart";
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
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
        
        // We STOP here. The user must manually press 'Proceed' to continue.
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
      User? currentUser = FirebaseAuth.instance.currentUser;
      
      // If user is not automatically logged in by Android Auto-Retrieval, sign them in manually
      if (currentUser == null) {
        PhoneAuthCredential credential = PhoneAuthProvider.credential(
          verificationId: widget.verificationId,
          smsCode: otp,
        );

        UserCredential userCredential =
            await FirebaseAuth.instance.signInWithCredential(credential);
        currentUser = userCredential.user;
      }

      if (currentUser != null) {
        // Successful login, check if user exists in Firestore
        final uid = currentUser.uid;
        
        final userDoc = await FirebaseFirestore.instance
            .collection('users')
            .doc(uid)
            .get();

        if (mounted) {
          if (userDoc.exists) {
            // Profile exists in users collection (Male Caller)
            final data = userDoc.data() ?? {};

            // Load app state
            final appState = context.read<AppState>();
            appState.setMobileNumber(widget.mobileNumber);
            appState.setSelectedGender('Male');
            appState.setNickname((data['nickname'] ?? '').toString());
            
            // Navigate to Dashboard
            Navigator.pushAndRemoveUntil(
              context,
              MaterialPageRoute(builder: (context) => const MaleCallerDashboard()),
              (route) => false,
            );
          } else {
            // Check if user exists in experts collection (Female Expert)
            final expertDoc = await FirebaseFirestore.instance
                .collection('experts')
                .doc(uid)
                .get();

            if (expertDoc.exists) {
              final data = expertDoc.data() ?? {};

              // Load app state
              final appState = context.read<AppState>();
              appState.setMobileNumber(widget.mobileNumber);
              appState.setSelectedGender('Female');
              appState.setNickname((data['nickname'] ?? '').toString());
              appState.setAudioVerified(true);
              
              // Navigate to Female Expert Dashboard
              Navigator.pushAndRemoveUntil(
                context,
                MaterialPageRoute(builder: (context) => const MainNavigation()),
                (route) => false,
              );
            } else {
              // New user, navigate to Gender Selection to build profile
              Navigator.pushReplacement(
                context,
                MaterialPageRoute(builder: (context) => const GenderSelectionScreen()),
              );
            }
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
    } catch (e) {
      debugPrint("OTP Verification Error: \$e");
      debugPrint("Stack Trace: \$stackTrace");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('An error occurred: \$e')),
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
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        toolbarHeight: 0,
        systemOverlayStyle: const SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: Brightness.dark,
          statusBarBrightness: Brightness.light,
        ),
      ),
      body: Stack(
        children: [
          // Background soft glow
          Center(
            child: Container(
              width: 300,
              height: 300,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    const Color(0xFF4C75F2).withValues(alpha: 0.15),
                    Colors.white.withValues(alpha: 0.0),
                  ],
                  stops: const [0.0, 1.0],
                ),
              ),
            ),
          ),
          SafeArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 60),
                
                // Instructions Text
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24.0),
                  child: RichText(
                    textAlign: TextAlign.center,
                    text: TextSpan(
                      style: const TextStyle(
                        fontSize: 15,
                        color: Colors.black54,
                        height: 1.4,
                      ),
                      children: [
                        TextSpan(text: 'Your login OTP is sent to +91 ${widget.mobileNumber}.\n'),
                        const TextSpan(text: 'Not your number? '),
                        TextSpan(
                          text: 'Change here.',
                          style: const TextStyle(
                            color: Colors.black87,
                            fontWeight: FontWeight.w600,
                            decoration: TextDecoration.underline,
                          ),
                          recognizer: TapGestureRecognizer()..onTap = () {
                            Navigator.pop(context);
                          },
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 40),
                
                // OTP Field with Gradient Border
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24.0),
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(8),
                      color: const Color(0xFF4C75F2), // Solid blue border
                    ),
                    padding: const EdgeInsets.all(1.5), // Border thickness
                    child: Container(
                      clipBehavior: Clip.antiAlias,
                      decoration: BoxDecoration(
                        color: Colors.white, // Inner background
                        borderRadius: BorderRadius.circular(7), // Slightly less than outer radius
                      ),
                      child: TextField(
                        controller: _otpController,
                        keyboardType: TextInputType.number,
                        maxLength: 6,
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w500,
                          color: Colors.black87,
                          letterSpacing: 2,
                        ),
                        decoration: const InputDecoration(
                          counterText: "",
                          border: InputBorder.none,
                          focusedBorder: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          errorBorder: InputBorder.none,
                          disabledBorder: InputBorder.none,
                          filled: true,
                          fillColor: Colors.transparent,
                          contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                        ),
                        // Removed auto-verify from onChanged
                        onChanged: (value) {},
                      ),
                    ),
                  ),
                ),
                
                const SizedBox(height: 30),
                
                // Proceed Button
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 70.0),
                  child: ElevatedButton(
                    onPressed: _isLoading ? null : _verifyOtp,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF4C75F2),
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(30),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    child: _isLoading
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 2,
                            ),
                          )
                        : const Text(
                            'Proceed',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                  ),
                ),
                
                const SizedBox(height: 24),
                
                // Resend OTP
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24.0),
                  child: RichText(
                    textAlign: TextAlign.center,
                    text: TextSpan(
                      style: const TextStyle(
                        fontSize: 14,
                        color: Colors.black87,
                      ),
                      children: [
                        const TextSpan(text: "Didn't receive an OTP? "),
                        TextSpan(
                          text: 'Resend code',
                          style: const TextStyle(
                            color: Color(0xFF4C75F2),
                          ),
                          recognizer: TapGestureRecognizer()..onTap = () async {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Resending OTP...')),
                            );
                            await FirebaseAuth.instance.verifyPhoneNumber(
                              phoneNumber: '+91${widget.mobileNumber}',
                              verificationCompleted: (PhoneAuthCredential credential) {},
                              verificationFailed: (FirebaseAuthException e) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text('Failed to resend: ${e.message}')),
                                );
                              },
                              codeSent: (String verificationId, int? resendToken) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('OTP sent successfully!')),
                                );
                              },
                              codeAutoRetrievalTimeout: (String verificationId) {},
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
