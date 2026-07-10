import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_fonts/google_fonts.dart';
import '../providers/app_state.dart';
import '../models/female_expert.dart';
import 'phone_auth_screen.dart';
import 'wallet_recharge_screen.dart';
import 'matchmaking_screen.dart';
import 'incoming_call_screen.dart';
import '../widgets/local_avatar_widget.dart';
import '../services/call_service.dart';
import '../services/notification_service.dart';
import '../services/hybrid_chat_service.dart';
import 'chat_list_screen.dart';
import 'hybrid_chat_screen.dart';
import 'expert_feed_screen.dart';
import '../utils/auto_start_helper.dart';
import '../services/foreground_task_service.dart';

class MaleCallerDashboard extends StatefulWidget {
  const MaleCallerDashboard({super.key});

  @override
  State<MaleCallerDashboard> createState() => _MaleCallerDashboardState();
}

class _MaleCallerDashboardState extends State<MaleCallerDashboard> {
  // Removed unused _callService

  // Navigation & filter states
  int _currentTab = 0; // 0 for Home, 1 for Recents, 2 for Chats
  bool _isOnlineSwitch = true;

  // Modern Color Palette Constants
  static const Color brandBg = Color(0xFFF8FAFC); // Slate 50
  static const Color brandPrimary = Color(0xFF4F46E5); // Indigo 600
  static const Color brandTextDark = Color(0xFF0F172A); // Slate 900
  static const Color brandTextGrey = Color(0xFF64748B); // Slate 500
  static const Color brandCardBg = Colors.white;

  // (Pagination and old expert list removed for RTDB bucket system)
  
  StreamSubscription? _incomingCallSubscription;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      // Ensure we have a valid Firebase Auth session (anonymous) so Firestore
      // rules (request.auth != null) are satisfied before any reads.
      if (FirebaseAuth.instance.currentUser == null) {
        try {
          await FirebaseAuth.instance.signInAnonymously();
          debugPrint('[MALE_DASH] signInAnonymously success uid=${FirebaseAuth.instance.currentUser?.uid}');
        } catch (e) {
          debugPrint('[MALE_DASH] signInAnonymously error: $e');
        }
      } else {
        debugPrint('[MALE_DASH] already signed in uid=${FirebaseAuth.instance.currentUser?.uid}');
      }

      if (!mounted) return;

      _setupMalePresenceAndCallListener();
      _fetchInitialWalletBalance();
      // Initialize Chat Listeners
      final appState = context.read<AppState>();
      final myUid = appState.mobileNumber.isNotEmpty ? appState.mobileNumber : "test_mobile";
      HybridChatService().initListeners(myUid);
      LocalChatDatabase.instance.syncCallLogsFromFirestore(myUid);
      
      // Check for auto-start permissions (Infinix, Xiaomi, etc.)
      AutoStartHelper.checkAndRequestAutoStart(context);
      
      // Keep app alive in background (always ON for male users)
      ForegroundTaskService.startService();
    });
  }

  void _setupMalePresenceAndCallListener() {
    final appState = context.read<AppState>();
    final mobile = appState.mobileNumber.isNotEmpty ? appState.mobileNumber : "test_mobile";
    
    // Setup RTDB Presence
    final presenceRef = FirebaseDatabase.instanceFor(
      app: FirebaseDatabase.instance.app,
      databaseURL: 'https://zegochat-c44b0.asia-southeast1.firebasedatabase.app',
    ).ref('status/$mobile');
    
    presenceRef.set({
      'isOnline': true,
      'status': 'online',
      'lastChanged': ServerValue.timestamp,
    });
    presenceRef.onDisconnect().update({
      'isOnline': false,
      'status': 'offline',
      'lastChanged': ServerValue.timestamp,
    });

    // Listen for incoming calls
    _incomingCallSubscription = CallService().listenForIncomingCalls(
      expertId: mobile, // Male user receives the call
      onCallReceived: (roomId, callerId) {
        if (!mounted) return;
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => IncomingCallScreen(
              callRoomId: roomId,
              callerId: callerId,
            ),
          ),
        );
      },
    );
  }

  @override
  void dispose() {
    HybridChatService().dispose();
    _incomingCallSubscription?.cancel();
    super.dispose();
  }

  // (Old _onScroll, _refreshExperts, _fetchExperts removed)

  Future<void> _fetchInitialWalletBalance() async {
    final appState = context.read<AppState>();
    final mobile = appState.mobileNumber.isNotEmpty ? appState.mobileNumber : "test_mobile";
    try {
      final docSnap = await FirebaseFirestore.instance.collection('users').doc(mobile).get();
      if (docSnap.exists) {
        final balance = (docSnap.data()?['walletBalance'] as num?)?.toDouble() ?? 0.0;
        final hasUsedFreeCall = docSnap.data()?['hasUsedFreeCall'] as bool? ?? false;
        appState.setWalletBalance(balance);
        appState.setHasUsedFreeCall(hasUsedFreeCall);
        
        final nickname = docSnap.data()?['nickname'] as String? ?? '';
        if (nickname.isNotEmpty) {
          appState.setNickname(nickname);
        }
      } else {
        await FirebaseFirestore.instance.collection('users').doc(mobile).set({
          'mobileNumber': mobile,
          'walletBalance': 0.0,
          'hasUsedFreeCall': false,
          'gender': 'male',
        }, SetOptions(merge: true));
        appState.setWalletBalance(0.0);
        appState.setHasUsedFreeCall(false);
      }
      
      // Save FCM Token for push notifications
      await NotificationService.instance.saveTokenForUser(
        userId: mobile,
        collection: 'users',
      );
    } catch (e) {
      debugPrint("Error fetching wallet balance: $e");
    }
  }

  void _logout() {
    context.read<AppState>().reset();
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (context) => const PhoneAuthScreen()),
      (route) => false,
    );
  }

  void _addMoneyDialog() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const WalletRechargeScreen()),
    );
  }

  void _triggerCall(FemaleExpert expert) async {
    try {
      final rtdb = FirebaseDatabase.instanceFor(
        app: FirebaseDatabase.instance.app,
        databaseURL: 'https://zegochat-c44b0.asia-southeast1.firebasedatabase.app',
      );
      final event = await rtdb.ref('status/${expert.id}/isOnline').once();
      bool isOnline = false;
      if (event.snapshot.value != null) {
        isOnline = event.snapshot.value == true;
      }
      
      if (!isOnline) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('${expert.nickname} is currently offline. Routing to another expert...')),
          );
          _startRandomMatchmaking();
        }
        return;
      }
    } catch (e) {
      debugPrint('Error checking RTDB status: $e');
    }

    if (!mounted) return;
    final appState = context.read<AppState>();
    final balance = appState.walletBalance;
    final hasUsedFreeCall = appState.hasUsedFreeCall;
    if (balance < expert.pricePerMin && hasUsedFreeCall) {
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text(
            'Insufficient Balance',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          content: Text(
            'Your wallet balance is ₹${balance.toStringAsFixed(2)}. You need at least ₹${expert.pricePerMin} to place a call.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text(
                'Cancel',
                style: TextStyle(color: brandTextGrey),
              ),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(context);
                _addMoneyDialog();
              },
              style: ElevatedButton.styleFrom(backgroundColor: brandPrimary),
              child: const Text('Recharge'),
            ),
          ],
        ),
      );
      return;
    }

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => MatchmakingScreen(
          requestedExpert: expert,
          isRandomMode: false,
        ),
      ),
    );
  }

  void _startRandomMatchmaking() {
    final appState = context.read<AppState>();
    final balance = appState.walletBalance;
    final hasUsedFreeCall = appState.hasUsedFreeCall;
    const pricePerMin = 5.0;
    if (balance < pricePerMin && hasUsedFreeCall) {
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text(
            'Insufficient Balance',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          content: Text(
            'Your wallet balance is ₹${balance.toStringAsFixed(2)}. You need at least ₹$pricePerMin to place a call.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text(
                'Cancel',
                style: TextStyle(color: brandTextGrey),
              ),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(context);
                _addMoneyDialog();
              },
              style: ElevatedButton.styleFrom(backgroundColor: brandPrimary),
              child: const Text('Recharge'),
            ),
          ],
        ),
      );
      return;
    }

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const MatchmakingScreen(
          isRandomMode: true,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: brandBg,
      body: SafeArea(
        child: _currentTab == 0 
            ? _buildHomeTab() 
            : _currentTab == 1 
                ? _buildRecentsTab() 
                : const ChatListScreen(),
      ),
      bottomNavigationBar: Container(
        height: 64,
        margin: const EdgeInsets.only(left: 16, right: 16, bottom: 16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 16,
              offset: const Offset(0, -2),
            ),
          ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            // Home Tab Button
            GestureDetector(
              onTap: () {
                setState(() {
                  _currentTab = 0;
                });
              },
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                decoration: _currentTab == 0
                    ? BoxDecoration(
                        color: brandPrimary.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(16),
                      )
                    : null,
                child: Row(
                  children: [
                    Icon(
                      _currentTab == 0
                          ? Icons.home_rounded
                          : Icons.home_outlined,
                      color: _currentTab == 0 ? brandPrimary : brandTextGrey,
                      size: 22,
                    ),
                    if (_currentTab == 0) ...[
                      const SizedBox(width: 8),
                      const Text(
                        'Home',
                        style: TextStyle(
                          color: brandPrimary,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            // Recents Tab Button
            GestureDetector(
              onTap: () {
                setState(() {
                  _currentTab = 1;
                });
              },
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                decoration: _currentTab == 1
                    ? BoxDecoration(
                        color: brandPrimary.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(16),
                      )
                    : null,
                child: Row(
                  children: [
                    Icon(
                      _currentTab == 1
                          ? Icons.access_time_filled_rounded
                          : Icons.access_time_rounded,
                      color: _currentTab == 1 ? brandPrimary : brandTextGrey,
                      size: 22,
                    ),
                    if (_currentTab == 1) ...[
                      const SizedBox(width: 8),
                      const Text(
                        'Recents',
                        style: TextStyle(
                          color: brandPrimary,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            // Chats Tab Button
            GestureDetector(
              onTap: () {
                setState(() {
                  _currentTab = 2;
                });
              },
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                decoration: _currentTab == 2
                    ? BoxDecoration(
                        color: brandPrimary.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(16),
                      )
                    : null,
                child: Row(
                  children: [
                    Icon(
                      _currentTab == 2
                          ? Icons.chat_bubble_rounded
                          : Icons.chat_bubble_outline_rounded,
                      color: _currentTab == 2 ? brandPrimary : brandTextGrey,
                      size: 22,
                    ),
                    if (_currentTab == 2) ...[
                      const SizedBox(width: 8),
                      const Text(
                        'Chats',
                        style: TextStyle(
                          color: brandPrimary,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Home Tab view (Redesigned 60-70% similar)
  Widget _buildHomeTab() {
    final appState = context.watch<AppState>();

    return SingleChildScrollView(
      child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
            // Redesigned Top Custom Header Row
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Row(
                children: [
                  Text(
                    'SajniRe',
                    style: GoogleFonts.yellowtail(
                      fontSize: 34,
                      fontWeight: FontWeight.bold,
                      color: brandTextDark,
                    ),
                  ),
                  const Spacer(),
                  // Wallet Pill (Redesigned with Slate 800 + Amber tag)
                  GestureDetector(
                    onTap: _addMoneyDialog,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1E293B),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(
                                colors: [Color(0xFFF59E0B), Color(0xFFD97706)],
                              ),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Text(
                              '% Sale',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 9,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            '₹${appState.walletBalance.toStringAsFixed(2)}',
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                            ),
                          ),
                          const SizedBox(width: 6),
                          const Icon(
                            Icons.add_circle_outline_rounded,
                            color: Colors.amber,
                            size: 14,
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // Wallet Recharge Banner
            GestureDetector(
              onTap: _addMoneyDialog,
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                decoration: BoxDecoration(
                  color: const Color(0xFF1E1B4B), // Deep Indigo dark
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.15),
                      blurRadius: 16,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    // Coin/wallet icon block
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF59E0B).withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: const Text('💰', style: TextStyle(fontSize: 26)),
                    ),
                    const SizedBox(width: 14),
                    // Text
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Recharge your wallet',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          SizedBox(height: 3),
                          Text(
                            'Talk more, pay less — top up now!',
                            style: TextStyle(
                              color: Color(0xFF94A3B8),
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                    // Add money chip
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFFF59E0B), Color(0xFFEF4444)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Text(
                        'Add ₹',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // FIRST 2 MIN FREE Banner
            if (!appState.hasUsedFreeCall)
              GestureDetector(
                onTap: _startRandomMatchmaking,
                child: Container(
                  margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF7C3AED), Color(0xFFEC4899)],
                      begin: Alignment.centerLeft,
                      end: Alignment.centerRight,
                    ),
                    borderRadius: BorderRadius.circular(24),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF7C3AED).withValues(alpha: 0.35),
                        blurRadius: 20,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      // Gift icon
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.2),
                          shape: BoxShape.circle,
                        ),
                        child: const Text('🎁', style: TextStyle(fontSize: 22)),
                      ),
                      const SizedBox(width: 14),
                      // Main text
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'FIRST 2 MIN FREE!',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 18,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 0.8,
                              ),
                            ),
                            SizedBox(height: 3),
                            Text(
                              'Tap to connect now ✨',
                              style: TextStyle(
                                color: Colors.white70,
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                      // Arrow
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.2),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.arrow_forward_rounded,
                          color: Colors.white,
                          size: 20,
                        ),
                      ),
                    ],
                  ),
                ),
              ),

            // Section Header
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16.0, vertical: 4.0),
              child: Text(
                'Featured Experts',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: brandTextDark,
                ),
              ),
            ),
            const SizedBox(height: 8),




            // Integrated Expert Feed Screen (Fetch Once)
            const ExpertFeedScreen(),
          ],
        ),
      );
  }

  void _triggerCallByExpertId(String expertId) async {
    try {
      final doc = await FirebaseFirestore.instance.collection('experts').doc(expertId).get();
      if (doc.exists) {
        final data = doc.data() as Map<String, dynamic>;
        
        bool isOnline = false;
        try {
          final rtdb = FirebaseDatabase.instanceFor(
            app: FirebaseDatabase.instance.app,
            databaseURL: 'https://zegochat-c44b0.asia-southeast1.firebasedatabase.app',
          );
          final event = await rtdb.ref('status/$expertId/isOnline').once();
          if (event.snapshot.value != null) {
            isOnline = event.snapshot.value == true;
          }
        } catch (e) {
          debugPrint('Error fetching RTDB status: $e');
        }

        final expert = FemaleExpert(
          id: doc.id,
          nickname: data['nickname'] ?? 'Expert',
          pricePerMin: (data['pricePerMin'] as num?)?.toInt() ?? 5,
          languages: data['languages'] ?? 'Hindi',
          rating: (data['rating'] ?? 4.5).toDouble(),
          isOnline: isOnline,
        );
        _triggerCall(expert);
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Expert not found')));
        }
      }
    } catch (e) {
      debugPrint('Error fetching expert: $e');
    }
  }

  // Redesigned Recents Tab view (60-70% similar)
  Widget _buildRecentsTab() {
    final appState = context.watch<AppState>();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 10.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header Row
          Row(
            children: [
              const Text(
                'Recents',
                style: TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.w900,
                  color: brandTextDark,
                ),
              ),
              const Spacer(),


            ],
          ),
          const SizedBox(height: 16),
          
          Expanded(
            child: StreamBuilder<void>(
              stream: LocalChatDatabase.instance.updates,
              builder: (context, snapshot) {
                return FutureBuilder<List<Map<String, dynamic>>>(
                  future: LocalChatDatabase.instance.getRecentCallLogs(appState.mobileNumber),
                  builder: (context, futureSnapshot) {
                if (futureSnapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                final docs = futureSnapshot.data ?? [];
                if (docs.isEmpty) {
                  return const Center(
                    child: Text('No recent calls', style: TextStyle(color: brandTextGrey)),
                  );
                }

                return ListView.builder(
                  itemCount: docs.length,
                  itemBuilder: (context, index) {
                    final data = docs[index];
                    final expertId = data['receiverId'] == appState.mobileNumber ? data['callerId'] : data['receiverId'];
                    final durationSeconds = data['durationSeconds'] ?? 0;
                    
                    final m = durationSeconds ~/ 60;
                    final s = durationSeconds % 60;
                    final durationStr = '${m}m ${s}s';
                    
                    String formattedTime = 'Just now';
                    if (data['timestamp'] != null) {
                      final dt = DateTime.fromMillisecondsSinceEpoch(data['timestamp']);
                      final now = DateTime.now();
                      if (dt.year == now.year && dt.month == now.month && dt.day == now.day) {
                        formattedTime = TimeOfDay.fromDateTime(dt).format(context);
                      } else {
                        formattedTime = '${dt.day}/${dt.month}';
                      }
                    }

                    return FutureBuilder<DocumentSnapshot>(
                      future: FirebaseFirestore.instance.collection('experts').doc(expertId).get(),
                      builder: (context, expertSnap) {
                        String displayName = expertId;
                        
                        if (expertSnap.hasData && expertSnap.data!.exists) {
                          final expertData = expertSnap.data!.data() as Map<String, dynamic>?;
                          if (expertData != null) {
                            displayName = expertData['nickname'] ?? displayName;
                          }
                        }

                        return Container(
                          margin: const EdgeInsets.only(bottom: 16),
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: brandCardBg,
                            borderRadius: BorderRadius.circular(24),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.03),
                                blurRadius: 12,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: Row(
                            children: [
                              // Avatar
                              Container(
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: Colors.blue.shade200,
                                    width: 1.5,
                                  ),
                                ),
                                child: LocalAvatarWidget(
                                  uid: expertId,
                                  role: 'expert',
                                  radius: 28,
                                ),
                              ),
                              const SizedBox(width: 16),

                              // Details
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Expanded(
                                          child: Text(
                                            displayName,
                                            style: const TextStyle(
                                              fontSize: 16,
                                              fontWeight: FontWeight.bold,
                                              color: brandTextDark,
                                            ),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                      ],
                                    ),
                                const SizedBox(height: 4),
                                Text(
                                  '$durationStr • $formattedTime',
                                  style: const TextStyle(color: brandTextGrey, fontSize: 13),
                                ),
                              ],
                            ),
                          ),

                          // Call Button
                          GestureDetector(
                            onTap: () => _triggerCallByExpertId(expertId),
                            child: Container(
                              width: 44,
                              height: 44,
                              decoration: BoxDecoration(
                                color: brandPrimary,
                                shape: BoxShape.circle,
                                boxShadow: [
                                  BoxShadow(
                                    color: brandPrimary.withValues(alpha: 0.2),
                                    blurRadius: 8,
                                    offset: const Offset(0, 4),
                                  ),
                                ],
                              ),
                              child: const Icon(
                                Icons.phone_in_talk_rounded,
                                color: Colors.white,
                                size: 20,
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                      },
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  // Redesigned Expert List Card (60-70% similar, organic rounded shape, soft styling)
  Widget _buildExpertItemRedesigned(FemaleExpert expert) {
    // Pick a soft accent color per expert based on name hash
    final accentColors = [
      const Color(0xFFEC4899), // pink
      const Color(0xFF8B5CF6), // purple
      const Color(0xFF06B6D4), // cyan
      const Color(0xFFF59E0B), // amber
      const Color(0xFF10B981), // emerald
      const Color(0xFFF43F5E), // rose
    ];
    final accentColor = accentColors[expert.nickname.hashCode.abs() % accentColors.length];

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // Avatar with live online indicator (RTDB - Low Cost)
                Stack(
                  children: [
                    LocalAvatarWidget(
                      uid: expert.id,
                      role: 'expert',
                      radius: 32,
                    ),
                    Positioned(
                      bottom: 2,
                      right: 2,
                      child: StreamBuilder<DatabaseEvent>(
                        stream: FirebaseDatabase.instanceFor(
                          app: FirebaseDatabase.instance.app,
                          databaseURL: 'https://zegochat-c44b0.asia-southeast1.firebasedatabase.app',
                        ).ref('status/${expert.id}/isOnline').onValue,
                        builder: (context, snapshot) {
                          Color statusColor = Colors.grey;

                          if (snapshot.connectionState == ConnectionState.waiting) {
                            if (expert.isOnline) {
                              statusColor = const Color(0xFF22C55E); // Green
                            }
                          } else {
                            if (snapshot.hasData && snapshot.data!.snapshot.value == true) {
                              statusColor = const Color(0xFF22C55E); // Green
                            } else {
                              statusColor = Colors.grey; // Offline
                            }
                          }

                          return Container(
                            width: 11,
                            height: 11,
                            decoration: BoxDecoration(
                              color: statusColor,
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.white, width: 2),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(width: 12),

                // Details
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Name row
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              expert.nickname,
                              style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w800,
                                color: brandTextDark,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 4),
                          // Rating pill
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFFFBEB),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(color: const Color(0xFFFCD34D), width: 1),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.star_rounded, size: 11, color: Color(0xFFF59E0B)),
                                const SizedBox(width: 2),
                                Text(
                                  expert.rating.toStringAsFixed(1),
                                  style: const TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                    color: Color(0xFFB45309),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      // Age, language in one line
                      Text(
                        '${expert.displayAge}y · ${expert.languages}',
                        style: const TextStyle(
                          fontSize: 11,
                          color: brandTextGrey,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),

                // Right: Price + Call button
                Column(
                  children: [
                    Text(
                      '₹${expert.pricePerMin}/min',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        color: accentColor,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Chat Button
                        GestureDetector(
                          onTap: () {
                             final appState = context.read<AppState>();
                             final myUid = appState.mobileNumber.isNotEmpty ? appState.mobileNumber : "test_mobile";
                             Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => HybridChatScreen(
                                    myUid: myUid,
                                    otherUid: expert.id,
                                    otherUserName: expert.nickname,
                                  ),
                                ),
                              );
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
                            decoration: BoxDecoration(
                              color: accentColor.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: Icon(Icons.chat_bubble_rounded, color: accentColor, size: 16),
                          ),
                        ),
                        const SizedBox(width: 6),
                        // Call Button
                        GestureDetector(
                          onTap: () => _triggerCall(expert),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                            decoration: BoxDecoration(
                              color: accentColor,
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.call_rounded, color: Colors.white, size: 14),
                                SizedBox(width: 4),
                                Text(
                                  'Call',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

