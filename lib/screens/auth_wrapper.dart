import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:provider/provider.dart';
import '../providers/app_state.dart';
import 'phone_auth_screen.dart';
import 'main_navigation.dart';
import 'gender_selection_screen.dart';
import '../theme/app_theme.dart';

class AuthWrapper extends StatefulWidget {
  const AuthWrapper({super.key});

  @override
  State<AuthWrapper> createState() => _AuthWrapperState();
}

class _AuthWrapperState extends State<AuthWrapper> {
  bool _isLoading = true;
  Widget _homeWidget = const PhoneAuthScreen();
  StreamSubscription<User?>? _authSubscription;

  @override
  void initState() {
    super.initState();
    _setupAuthListener();
  }

  void _setupAuthListener() {
    _authSubscription = FirebaseAuth.instance.authStateChanges().listen((User? user) {
      _checkAuthState(user);
    });
  }

  @override
  void dispose() {
    _authSubscription?.cancel();
    super.dispose();
  }

  Future<void> _checkAuthState(User? user) async {
    final String? rawPhone = user?.phoneNumber ?? user?.displayName;
    
    if (user != null && rawPhone != null && rawPhone.isNotEmpty) {
      // User is logged in, check if they have a profile in Firestore
      try {
        final String mobileNumber = rawPhone.replaceAll('+91', '');
        
        final userDoc = await FirebaseFirestore.instance
            .collection('users')
            .doc(mobileNumber)
            .get();

        if (mounted) {
          if (userDoc.exists) {
            // Profile exists, load data into AppState
            final data = userDoc.data()!;
            final gender = data['gender'] ?? 'male';

            final appState = context.read<AppState>();
            appState.setMobileNumber(mobileNumber);
            appState.setSelectedGender(gender == 'male' ? 'Male' : 'Female');
            appState.setNickname(data['nickname'] ?? '');
            
            setState(() {
              _homeWidget = const MainNavigation();
              _isLoading = false;
            });
          } else {
            // Logged in but no profile (maybe they closed the app during onboarding)
            final appState = context.read<AppState>();
            appState.setMobileNumber(mobileNumber);
            
            setState(() {
              _homeWidget = const GenderSelectionScreen();
              _isLoading = false;
            });
          }
        }
      } catch (e) {
        debugPrint("Error checking user profile: $e");
        if (mounted) {
          setState(() {
            _homeWidget = const PhoneAuthScreen();
            _isLoading = false;
          });
        }
      }
    } else {
      // No user logged in
      if (mounted) {
        setState(() {
          _homeWidget = const PhoneAuthScreen();
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        body: Center(
          child: CircularProgressIndicator(
            color: AppTheme.primaryBlue,
          ),
        ),
      );
    }

    return _homeWidget;
  }
}
