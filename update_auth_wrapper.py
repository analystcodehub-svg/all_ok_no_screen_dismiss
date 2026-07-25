import re

with open('lib/screens/auth_wrapper.dart', 'r') as f:
    content = f.read()

new_check_auth_state = """  Future<void> _checkAuthState(User? user) async {
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
          if (userDoc.exists) {
            // Profile exists, load data into AppState
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
  }"""

content = re.sub(
    r"Future<void> _checkAuthState\(User\? user\) async \{.*?(?=\n  @override\n  Widget build)",
    new_check_auth_state + "\n",
    content,
    flags=re.DOTALL
)

with open('lib/screens/auth_wrapper.dart', 'w') as f:
    f.write(content)
