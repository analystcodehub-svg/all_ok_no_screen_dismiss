import 'dart:async';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:provider/provider.dart';
import '../providers/app_state.dart';
import 'phone_auth_screen.dart';
import 'main_navigation.dart';
import 'gender_selection_screen.dart';
import '../theme/app_theme.dart';
import 'male_dashboard_screen.dart';
import '../services/block_service.dart';

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
    final prefs = await SharedPreferences.getInstance();
    final String? savedPhone = prefs.getString('saved_mobile');
    
    final String? savedEmail = prefs.getString('saved_email');
    final String? savedPassword = prefs.getString('saved_password');
    
    // Auto-restore email session if Firebase dropped it
    if (user == null && savedEmail != null && savedPassword != null) {
      try {
        await FirebaseAuth.instance.signInWithEmailAndPassword(
          email: savedEmail,
          password: savedPassword,
        );
        user = FirebaseAuth.instance.currentUser;
      } catch (e) {
        debugPrint("Auto-login failed: $e");
      }
    }
    
    final String? rawPhone = user?.phoneNumber ?? user?.displayName ?? savedPhone;
    
    if (user != null && rawPhone != null && rawPhone.isNotEmpty) {
      // User is logged in, check if they have a profile in Firestore
      try {
        final String mobileNumber = rawPhone.replaceAll('+91', '');
        
        final userDoc = await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
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
            
            // Sync blocked users
            BlockService.instance.syncBlockedUsers(user.uid);
            
            setState(() {
              _homeWidget = gender == 'male' 
                  ? const MaleCallerDashboard() 
                  : const MainNavigation();
              _isLoading = false;
            });
          } else {
            // Logged in but no profile (maybe they closed the app during onboarding)
            final appState = context.read<AppState>();
            appState.setMobileNumber(mobileNumber);
            
            // Sync blocked users even during onboarding (just in case)
            BlockService.instance.syncBlockedUsers(user.uid);
            
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
