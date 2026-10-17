import "../utils/permission_helper.dart";
import "package:flutter/services.dart";
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_fonts/google_fonts.dart';
import '../providers/app_state.dart';
import '../models/female_expert.dart';
import 'wallet_recharge_screen.dart';
import 'matchmaking_screen.dart';
import 'incoming_call_screen.dart';
import 'profile_screen.dart';
import '../widgets/local_avatar_widget.dart';
import '../services/call_service.dart';
import '../services/notification_service.dart';
import '../services/hybrid_chat_service.dart';
import 'chat_list_screen.dart';

import 'expert_feed_screen.dart';
import '../utils/auto_start_helper.dart';
import '../services/foreground_task_service.dart';
import '../services/local_chat_database.dart';
import '../services/user_database_service.dart';
import '../services/new_male_service.dart';

class MaleCallerDashboard extends StatefulWidget {
  const MaleCallerDashboard({super.key});

  @override
  State<MaleCallerDashboard> createState() => _MaleCallerDashboardState();
}

class _MaleCallerDashboardState extends State<MaleCallerDashboard> {
  // Removed unused _callService

  // Navigation & filter states
  int _currentTab = 0; // 0 for Home, 1 for Recents, 2 for Chats

  // Modern Color Palette Constants
  static const Color brandBg = Color(0xFFF8FAFC); // Slate 50
  static const Color brandPrimary = Color(0xFF4F46E5); // Indigo 600
  static const Color brandTextDark = Color(0xFF0F172A); // Slate 900
  static const Color brandTextGrey = Color(0xFF64748B); // Slate 500
  static const Color brandCardBg = Colors.white;

  final ScrollController _homeScrollController = ScrollController();
  StreamSubscription? _incomingCallSubscription;
  StreamSubscription? _introCallSubscription;
  StreamSubscription? _walletSubscription;

  Future<List<Map<String, dynamic>>> _fetchEnrichedCallLogs(String uid) async {
    final docs = await LocalChatDatabase.instance.getRecentCallLogs(uid);
    final enriched = <Map<String, dynamic>>[];
    for (var data in docs) {
      final map = Map<String, dynamic>.from(data);
      final expertId = map['receiverId'] == uid ? map['callerId'] : map['receiverId'];
      
      String displayName = expertId;
      String? avatarUrl;
      int avatarIndex = 1;
      
      try {
        final cachedProfile = await LocalChatDatabase.instance.getUserProfile(expertId);
        if (cachedProfile != null) {
          displayName = cachedProfile['name'] as String? ?? expertId;
          avatarUrl = cachedProfile['avatarUrl'] as String?;
          avatarIndex = (cachedProfile['avatarIndex'] as num?)?.toInt() ?? 1;
        } else {
          final expertData = await UserDatabaseService.instance.getExpert(expertId);
          if (expertData != null) {
            displayName = expertData['nickname'] ?? expertData['name'] ?? expertId;
            avatarUrl = expertData['profileImageUrl'] ?? expertData['avatarUrl'];
            avatarIndex = (expertData['avatarIndex'] as num?)?.toInt() ?? 1;
            
            // Save to local cache
            await LocalChatDatabase.instance.saveUserProfile({
              'uid': expertId,
              'name': displayName,
              'avatarUrl': avatarUrl,
              'avatarIndex': avatarIndex,
              'role': 'expert',
              'timestamp': DateTime.now().millisecondsSinceEpoch,
            });
          }
        }
      } catch (e) {
        // Ignore errors, fallback to default
      }
      
      map['enrichedName'] = displayName;
      map['enrichedAvatarUrl'] = avatarUrl;
      map['enrichedAvatarIndex'] = avatarIndex;
      map['expertId'] = expertId;
      enriched.add(map);
    }
    return enriched;
  }

  int _unreadCount = 0;
  StreamSubscription<void>? _chatUpdatesSubscription;

  void _updateUnreadCount(String uid) async {
    final count = await LocalChatDatabase.instance.getTotalUnreadCount(uid);
    if (mounted) {
      setState(() {
        _unreadCount = count;
      });
    }
  }

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
      final myUid = appState.uid;
      HybridChatService.instance.initListeners(myUid);
      LocalChatDatabase.instance.syncCallLogsFromFirestore(myUid);
      
      // Update initial unread count and listen for updates
      _updateUnreadCount(myUid);
      _chatUpdatesSubscription = LocalChatDatabase.instance.updates.listen((_) {
        _updateUnreadCount(myUid);
      });
      
      // Check for auto-start permissions (Infinix, Xiaomi, etc.)
      AutoStartHelper.checkAndRequestAutoStart(context);
      
      // Check and request notification permissions gracefully via bottom sheet
      PermissionHelper.checkAndRequestNotificationPermission(context);
      
      // Keep app alive in background (always ON for male users)
      ForegroundTaskService.startService();
    });
  }



  void _showFreeMessagesPopup() {
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (BuildContext context) {
        return Dialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          elevation: 0,
          backgroundColor: Colors.transparent,
          child: Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(24),
              boxShadow: const [
                BoxShadow(color: Colors.black26, blurRadius: 10, offset: Offset(0, 10)),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: const BoxDecoration(
                    color: Color(0xFFEFF6FF),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.mark_chat_unread_rounded,
                    size: 48,
                    color: Color(0xFF3B82F6),
                  ),
                ),
                const SizedBox(height: 24),
                const Text(
                  '5 मुफ़्त मैसेज!',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF0F172A),
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                  'आपको मिले हैं 5 मुफ़्त चैट मैसेज!\nअपनी पसंदीदा एक्सपर्ट से तुरंत चैटिंग शुरू करें।',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 15,
                    color: Color(0xFF64748B),
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () {
                      Navigator.of(context).pop();
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF3B82F6),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: const Text(
                      'चैट शुरू करें',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showZeroBalancePopup() {
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (BuildContext context) {
        return Dialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          elevation: 0,
          backgroundColor: Colors.transparent,
          child: Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(24),
              boxShadow: const [
                BoxShadow(color: Colors.black26, blurRadius: 10, offset: Offset(0, 10)),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: const BoxDecoration(
                    color: Color(0xFFFEF3C7),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.account_balance_wallet_rounded,
                    size: 44,
                    color: Color(0xFFF59E0B),
                  ),
                ),
                const SizedBox(height: 20),
                const Text(
                  'Zero Balance (₹0)',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF0F172A),
                  ),
                ),
                const SizedBox(height: 10),
                const Text(
                  'Your wallet is empty. Recharge now (starting at just ₹20) to connect with experts via voice call and chat!',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 14,
                    color: Color(0xFF64748B),
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () {
                      Navigator.of(context).pop();
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (context) => const WalletRechargeScreen()),
                      );
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFF97316),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      elevation: 2,
                    ),
                    child: const Text(
                      'Recharge Wallet',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text(
                    'Maybe Later',
                    style: TextStyle(
                      color: Color(0xFF94A3B8),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _setupMalePresenceAndCallListener() {

    final appState = context.read<AppState>();
    final myUid = appState.uid;
    
    // Setup RTDB Presence
    final presenceRef = FirebaseDatabase.instanceFor(
      app: FirebaseDatabase.instance.app,
      databaseURL: 'https://zegochat-c44b0.asia-southeast1.firebasedatabase.app',
    ).ref('status/$myUid');
    
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
      expertId: myUid, // Male user receives the call
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

    // Listen for incoming 1-minute intro calls from female experts on new database (zegochat-c44b0-1e689)
    _introCallSubscription?.cancel();
    _introCallSubscription = CallService(
      databaseURL: NewMaleService.newDbUrl,
    ).listenForIncomingCalls(
      expertId: myUid,
      onCallReceived: (roomId, callerId) {
        if (!mounted) return;
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => IncomingCallScreen(
              callRoomId: roomId,
              callerId: callerId,
              callDatabaseURL: NewMaleService.newDbUrl,
              isFreeIntroCall: true,
            ),
          ),
        );
      },
    );

    // Sync male user to new_males_pool on new RTDB for female discovery
    NewMaleService.instance.registerOrUpdateMale(
      uid: myUid,
      nickname: appState.nickname,
      avatarUrl: '',
      avatarIndex: appState.avatarIndex,
      isOnline: true,
    );

    // Listen to real-time wallet balance changes
    _walletSubscription?.cancel();
    _walletSubscription = UserDatabaseService.instance.usersRef
        .child(myUid)
        .child('coinBalance')
        .onValue
        .listen((event) {
      if (event.snapshot.exists && event.snapshot.value != null && mounted) {
        final coins = (event.snapshot.value as num).toInt();
        context.read<AppState>().setCoinBalance(coins);
      }
    });
  }

  @override
  void dispose() {
    // We don't dispose the singleton, just let it run or implement a cleanup method if needed.
    // HybridChatService.instance.dispose();
    _chatUpdatesSubscription?.cancel();
    _incomingCallSubscription?.cancel();
    _introCallSubscription?.cancel();
    _walletSubscription?.cancel();
    _homeScrollController.dispose();
    super.dispose();
  }

  // (Old _onScroll, _refreshExperts, _fetchExperts removed)

  Future<void> _fetchInitialWalletBalance() async {
    final appState = context.read<AppState>();
    final myUid = appState.uid;
    try {
      final data = await UserDatabaseService.instance.getUser(myUid);
      if (data != null) {
        int coinBalance = (data['coinBalance'] as num?)?.toInt() ?? 0;
        final freeMessagesUsed = (data['freeMessagesUsed'] as num?)?.toInt() ?? 0;
        final bool seenFreeMessagesPopup = data['seenFreeMessagesPopup'] as bool? ?? false;
        appState.setCoinBalance(coinBalance);
        appState.setFreeMessagesUsed(freeMessagesUsed);

        // Show Free 5 Messages Popup in Hindi if not seen yet and free messages available
        if (!seenFreeMessagesPopup && freeMessagesUsed < 5) {
          await UserDatabaseService.instance.updateUser(myUid, {
            'seenFreeMessagesPopup': true,
          });
          if (mounted) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) _showFreeMessagesPopup();
            });
          }
        } else if (coinBalance <= 0 && mounted) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) _showZeroBalancePopup();
          });
        }
        
        final nickname = data['nickname'] as String? ?? '';
        if (nickname.isNotEmpty) {
          appState.setNickname(nickname);
        }
      } else {
        await UserDatabaseService.instance.setUser(myUid, {
          'uid': myUid,
          'coinBalance': 0,
          'seenFreeMessagesPopup': true,
          'createdAt': DateTime.now().millisecondsSinceEpoch,
          'freeMessagesUsed': 0,
          'gender': 'male',
        });
        appState.setCoinBalance(0);
        appState.setFreeMessagesUsed(0);
        
        if (mounted) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) _showFreeMessagesPopup();
          });
        }
      }
      
      // Save FCM Token for push notifications
      await NotificationService.instance.saveTokenForUser(
        userId: myUid,
        collection: 'users',
      );
    } catch (e) {
      debugPrint("Error fetching initial balance: $e");
    }
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
    final balance = appState.coinBalance;

    const overridePricePerMin = 3.0; // Enforce ₹3/min for male callers
    
    if (balance < (overridePricePerMin * 10).toInt()) {
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text(
            'Insufficient Balance',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          content: Text(
            'Your balance is ₹${(balance / 10).toStringAsFixed(1)}. You need at least ₹$overridePricePerMin to place a call.',
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
    final balance = appState.coinBalance;

    const requiredCoins = 30; // equivalent to ₹3/min
    
    if (balance < requiredCoins) {
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text(
            'Insufficient Balance',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          content: Text(
            'Your balance is ₹${(balance / 10).toStringAsFixed(1)}. You need at least ₹${(requiredCoins / 10).toStringAsFixed(1)} to start random matchmaking.',
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

  Widget _buildBody() {
    switch (_currentTab) {
      case 0: return _buildHomeTab();
      case 1: return _buildRecentsTab();
      case 2: return const ChatListScreen();
      case 3: return const ProfileScreen();
      default: return _buildHomeTab();
    }
  }

  Widget _buildIconWithBadge(IconData icon, String count, {bool isActive = false}) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Icon(icon, size: 26),
        if (count.isNotEmpty)
          Positioned(
            top: -4,
            right: -4,
            child: Container(
              padding: const EdgeInsets.all(4),
              decoration: const BoxDecoration(
                color: Colors.red,
                shape: BoxShape.circle,
              ),
              child: Text(
                count,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.dark,
        statusBarBrightness: Brightness.light,
        systemNavigationBarColor: Colors.white,
        systemNavigationBarIconBrightness: Brightness.dark,
      ),
      child: Scaffold(
        backgroundColor: brandBg,
        body: SafeArea(
          child: _buildBody(),
        ),
            bottomNavigationBar: Container(
        decoration: BoxDecoration(
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 10,
              offset: const Offset(0, -5),
            ),
          ],
        ),
        child: BottomNavigationBar(
          currentIndex: _currentTab,
          onTap: (index) {
            setState(() {
              _currentTab = index;
            });
          },
          type: BottomNavigationBarType.fixed,
          backgroundColor: Colors.white,
          selectedItemColor: brandPrimary,
          unselectedItemColor: Colors.grey.shade500,
          selectedLabelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
          unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.normal, fontSize: 12),
          items: [
            const BottomNavigationBarItem(
              icon: Icon(Icons.home_outlined, size: 26),
              activeIcon: Icon(Icons.home_rounded, size: 26),
              label: 'Home',
            ),
            const BottomNavigationBarItem(
              icon: Icon(Icons.access_time_rounded, size: 26),
              activeIcon: Icon(Icons.access_time_filled_rounded, size: 26),
              label: 'Recents',
            ),
            BottomNavigationBarItem(
              icon: _buildIconWithBadge(Icons.chat_bubble_outline_rounded, _unreadCount > 0 ? (_unreadCount > 99 ? '99+' : _unreadCount.toString()) : ''),
              activeIcon: _buildIconWithBadge(Icons.chat_bubble_rounded, _unreadCount > 0 ? (_unreadCount > 99 ? '99+' : _unreadCount.toString()) : '', isActive: true),
              label: 'Chat',
            ),
            const BottomNavigationBarItem(
              icon: Icon(Icons.person_outline_rounded, size: 26),
              activeIcon: Icon(Icons.person_rounded, size: 26),
              label: 'Profile',
            ),
          ],
        ),
      ),
    ),
    );
  }

  // Home Tab view (Redesigned 60-70% similar)
  Widget _buildHomeTab() {
    final appState = context.watch<AppState>();

    return SingleChildScrollView(
      controller: _homeScrollController,
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
                              '₹ Wallet',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 9,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            '₹${(appState.coinBalance / 10).toStringAsFixed(1)}',
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
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF1D4ED8), Color(0xFF2563EB), Color(0xFF3B82F6)], // Vibrant Blue
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(18),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF1D4ED8).withValues(alpha: 0.45),
                      blurRadius: 20,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(18),
                  child: Stack(
                    children: [
                      // Shine circle top-right
                      Positioned(
                        right: -20,
                        top: -20,
                        child: Container(
                          width: 100,
                          height: 100,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.white.withValues(alpha: 0.08),
                          ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                        child: Row(
                          children: [
                            // Icon
                            Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(14),
                              ),
                              child: const Text('💰', style: TextStyle(fontSize: 24)),
                            ),
                            const SizedBox(width: 14),
                            // Text block
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  RichText(
                                    text: const TextSpan(
                                      children: [
                                        TextSpan(
                                          text: 'Call only ',
                                          style: TextStyle(
                                            color: Colors.white,
                                            fontSize: 15,
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                        TextSpan(
                                          text: '₹3',
                                          style: TextStyle(
                                            color: Colors.yellowAccent,
                                            fontSize: 24,
                                            fontWeight: FontWeight.w900,
                                            letterSpacing: -0.5,
                                          ),
                                        ),
                                        TextSpan(
                                          text: '/min',
                                          style: TextStyle(
                                            color: Colors.yellowAccent,
                                            fontSize: 16,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            // Add button
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: const Text(
                                'Add ₹',
                                style: TextStyle(
                                  color: Color(0xFF1D4ED8),
                                  fontSize: 13,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),



            // Promotional Banner (5 FREE MESSAGES + SALE)
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                gradient: const LinearGradient(
                  colors: [Color(0xFF3B82F6), Color(0xFF1E3A8A)], // Vibrant Blue Gradient
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF1E3A8A).withValues(alpha: 0.3),
                    blurRadius: 15,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(20),
                child: Stack(
                  children: [
                    // Background pattern (optional shine)
                    Positioned(
                      right: -30,
                      top: -30,
                      child: Container(
                        width: 120,
                        height: 120,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.white.withValues(alpha: 0.1),
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (appState.freeMessagesUsed < 5) ...[
                            Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(8),
                                  decoration: const BoxDecoration(
                                    color: Colors.white,
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Text('💬', style: TextStyle(fontSize: 16)),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      const Text(
                                        '5 FREE MESSAGES!',
                                        style: TextStyle(
                                          color: Colors.white,
                                          fontSize: 16,
                                          fontWeight: FontWeight.w900,
                                          letterSpacing: 0.5,
                                        ),
                                      ),
                                      Text(
                                        'You have ${5 - appState.freeMessagesUsed} messages left ✨',
                                        style: const TextStyle(
                                          color: Colors.white70,
                                          fontSize: 13,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 16),
                            Divider(color: Colors.white.withValues(alpha: 0.2), height: 1),
                            const SizedBox(height: 16),
                          ],
                          
                          // Discount Offer Section
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFF59E0B), // Amber badge
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: const Text(
                                      'LIMITED TIME OFFER',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 10,
                                        fontWeight: FontWeight.bold,
                                        letterSpacing: 1,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  const Text(
                                    '40 Messages',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 20,
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                                ],
                              ),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  const Text(
                                    '₹40',
                                    style: TextStyle(
                                      color: Colors.white60,
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                      decoration: TextDecoration.lineThrough,
                                    ),
                                  ),
                                  Row(
                                    crossAxisAlignment: CrossAxisAlignment.baseline,
                                    textBaseline: TextBaseline.alphabetic,
                                    children: const [
                                      Text(
                                        '₹',
                                        style: TextStyle(
                                          color: Colors.yellowAccent,
                                          fontSize: 16,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                      Text(
                                        '20',
                                        style: TextStyle(
                                          color: Colors.yellowAccent,
                                          fontSize: 28,
                                          fontWeight: FontWeight.w900,
                                        ),
                                      ),
                                    ],
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
              ),
            ),

            // Section Header
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Featured Experts',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: brandTextDark,
                  ),
                ),
              ),
            ),

            // Integrated Expert Feed Screen (Live Real-Time Stream with Progressive Pagination)
            ExpertFeedScreen(scrollController: _homeScrollController),
          ],
        ),
      );
  }

  void _triggerCallByExpertId(String expertId) async {
    try {
      final data = await UserDatabaseService.instance.getExpert(expertId);
      if (data != null) {
        
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
          id: expertId,
          nickname: data['nickname'] ?? 'Expert',
          pricePerMin: (data['pricePerMin'] as num?)?.toInt() ?? 5,
          languages: data['languages'] ?? 'Hindi',
          rating: (data['rating'] ?? 4.5).toDouble(),
          isOnline: isOnline,
          avatarUrl: data['profileImageUrl'] ?? data['avatarUrl'],
          avatarIndex: (data['avatarIndex'] as num?)?.toInt() ?? 1,
          age: (data['age'] as num?)?.toInt() ?? 22,
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
                  future: _fetchEnrichedCallLogs(appState.uid),
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
                    final expertId = data['expertId'] as String;
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

                    final displayName = data['enrichedName'] as String;
                    final avatarUrl = data['enrichedAvatarUrl'] as String?;
                    final avatarIndex = data['enrichedAvatarIndex'] as int;

                    return Container(
                      margin: const EdgeInsets.only(bottom: 16),
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: brandCardBg,
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
                              avatarUrl: avatarUrl,
                              avatarIndex: avatarIndex,
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

}

