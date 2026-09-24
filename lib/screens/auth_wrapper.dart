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
  String? _errorMessage;

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
    // Clear error message if we proceed
    if (mounted && _errorMessage != null) {
      setState(() => _errorMessage = null);
    }
    
    if (user != null) {
      // User is logged in, check if they have a profile in Firestore
      try {
        final String? rawPhone = user.phoneNumber;
        // If phone auth, it usually has +91. Clean it.
        String mobileNumber = rawPhone?.replaceAll('+91', '') ?? '';
        
        final userDoc = await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .get();

        if (mounted) {
          if (!mounted) return;
          if (userDoc.exists) {
            // Profile exists in users collection (Male Caller)
            final data = userDoc.data()!;
            final gender = data['gender'] ?? 'male';

            final appState = context.read<AppState>();
            if (mobileNumber.isNotEmpty) {
              appState.setMobileNumber(mobileNumber);
            }
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
            // Check if user exists in experts collection (Female Expert)
            final expertDoc = await FirebaseFirestore.instance
                .collection('experts')
                .doc(user.uid)
                .get();

            if (!mounted) return;
            if (expertDoc.exists) {
              final data = expertDoc.data()!;
              
              final appState = context.read<AppState>();
              if (mobileNumber.isNotEmpty) {
                appState.setMobileNumber(mobileNumber);
              }
              appState.setSelectedGender('Female');
              appState.setNickname((data['nickname'] ?? '').toString());
              appState.setAudioVerified(true);
              
              BlockService.instance.syncBlockedUsers(user.uid);
              
              setState(() {
                _homeWidget = const MainNavigation();
                _isLoading = false;
              });
            } else {
              if (!mounted) return;
              // Logged in but no profile (maybe they closed the app during onboarding)
              final appState = context.read<AppState>();
              if (mobileNumber.isNotEmpty) {
                appState.setMobileNumber(mobileNumber);
              }
              
              // Sync blocked users even during onboarding (just in case)
              BlockService.instance.syncBlockedUsers(user.uid);
              
              setState(() {
                _homeWidget = const GenderSelectionScreen();
                _isLoading = false;
              });
            }
          }
        }
      } catch (e) {
        debugPrint("Error checking user profile: $e");
        if (mounted) {
          setState(() {
            _errorMessage = "Network error. Failed to load profile.";
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

    if (_errorMessage != null) {
      return Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.wifi_off_rounded, size: 64, color: Colors.grey),
                const SizedBox(height: 16),
                Text(
                  _errorMessage!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 16, color: Colors.black87),
                ),
                const SizedBox(height: 24),
                ElevatedButton(
                  onPressed: () {
                    setState(() {
                      _isLoading = true;
                      _errorMessage = null;
                    });
                    _checkAuthState(FirebaseAuth.instance.currentUser);
                  },
                  child: const Text('Retry'),
                ),
                TextButton(
                  onPressed: () async {
                    final prefs = await SharedPreferences.getInstance();
                    await prefs.clear();
                    await FirebaseAuth.instance.signOut();
                    if (mounted) {
                      setState(() {
                        _errorMessage = null;
                        _homeWidget = const PhoneAuthScreen();
                      });
                    }
                  },
                  child: const Text('Logout', style: TextStyle(color: Colors.grey)),
                )
              ],
            ),
          ),
        ),
      );
    }

    return _homeWidget;
  }
}
