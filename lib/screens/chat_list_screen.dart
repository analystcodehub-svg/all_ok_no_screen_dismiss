import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:permission_handler/permission_handler.dart';
import '../theme/app_colors.dart';
import '../providers/app_state.dart';
import '../services/local_chat_database.dart';
import '../widgets/local_avatar_widget.dart';
import 'hybrid_chat_screen.dart';
import '../services/user_database_service.dart';
import '../services/new_male_service.dart';
import '../services/call_service.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_database/firebase_database.dart';
import 'active_call_page.dart';
import '../services/matchmaking_service.dart';
import '../services/foreground_task_service.dart';
import '../models/female_expert.dart';
import 'wallet_recharge_screen.dart';
import 'matchmaking_screen.dart';

class ChatListScreen extends StatefulWidget {
  const ChatListScreen({super.key});

  @override
  State<ChatListScreen> createState() => _ChatListScreenState();
}

class _ChatListScreenState extends State<ChatListScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  late String _currentUserMobile;
  late final MatchmakingService _matchingService;
  Stream<List<Map<String, dynamic>>>? _newMalesStream;
  int _randomSeed = DateTime.now().millisecondsSinceEpoch;
  bool _isCallingUser = false;
  final Set<String> _pinnedUids = {};

  @override
  void initState() {
    super.initState();
    _matchingService = MatchmakingService();
    _tabController = TabController(length: 2, vsync: this);
    final appState = context.read<AppState>();
    _initNewMalesStream(appState.primaryLanguage);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  void _initNewMalesStream([String? lang]) {
    final appState = context.read<AppState>();
    final effectiveLang = lang ?? appState.primaryLanguage;
    final stream = NewMaleService.instance.streamNewMales(
      femaleLanguage: effectiveLang.isNotEmpty ? effectiveLang : 'Hindi',
      limit: 50,
      randomSeed: _randomSeed,
    );
    if (mounted) {
      setState(() {
        _newMalesStream = stream;
      });
    } else {
      _newMalesStream = stream;
    }
  }

  void _refreshNewMales([String? lang]) {
    _randomSeed = DateTime.now().millisecondsSinceEpoch;
    _initNewMalesStream(lang);
  }

  Future<List<Map<String, dynamic>>> _fetchEnrichedChats(String myUid, bool isCurrentMale) async {
    final chatDocs = await LocalChatDatabase.instance.getRecentChats(myUid);
    final enrichedDocs = <Map<String, dynamic>>[];

    for (var doc in chatDocs) {
      final data = Map<String, dynamic>.from(doc);
      final otherUser = data['otherUserId'] as String;
      
      String displayName = otherUser;
      
      // If current user is male, the other user must be an expert (female avatar).
      // If current user is female, the other user must be a user (male avatar).
      String role = isCurrentMale ? 'expert' : 'user';

      try {
        final cachedProfile = await LocalChatDatabase.instance.getUserProfile(otherUser);
        if (cachedProfile != null) {
          displayName = cachedProfile['name'] as String? ?? otherUser;
          data['avatarUrl'] = cachedProfile['avatarUrl'];
          data['avatarIndex'] = cachedProfile['avatarIndex'] ?? 1;
        } else {
          // Try experts first
          final expertData = await UserDatabaseService.instance.getExpert(otherUser);
          if (expertData != null) {
            String? eName = expertData['nickname']?.toString().trim();
            if (eName == null || eName.isEmpty) eName = expertData['name']?.toString().trim();
            if (eName == null || eName.isEmpty) eName = expertData['displayName']?.toString().trim();
            if (eName == null || eName.isEmpty) eName = expertData['fullName']?.toString().trim();
            
            if (eName != null && eName.isNotEmpty) {
              displayName = eName;
            }

            data['avatarUrl'] = expertData['profileImageUrl'] ?? expertData['avatarUrl'];
            data['avatarIndex'] = (expertData['avatarIndex'] as num?)?.toInt() ?? 1;
            
            await LocalChatDatabase.instance.saveUserProfile({
              'uid': otherUser,
              'name': displayName,
              'avatarUrl': data['avatarUrl'],
              'avatarIndex': data['avatarIndex'],
              'role': 'expert',
              'timestamp': DateTime.now().millisecondsSinceEpoch,
            });
          } else {
            // Try users
            final userData = await UserDatabaseService.instance.getUser(otherUser);
            if (userData != null) {
              String? uName = userData['nickname']?.toString().trim();
              if (uName == null || uName.isEmpty) uName = userData['name']?.toString().trim();
              if (uName == null || uName.isEmpty) uName = userData['displayName']?.toString().trim();
              if (uName == null || uName.isEmpty) uName = userData['fullName']?.toString().trim();
              
              if (uName != null && uName.isNotEmpty) {
                displayName = uName;
              } else {
                displayName = otherUser;
              }
              
              data['avatarUrl'] = userData['avatarUrl'];
              data['avatarIndex'] = (userData['avatarIndex'] as num?)?.toInt() ?? 1;
              
              await LocalChatDatabase.instance.saveUserProfile({
                'uid': otherUser,
                'name': displayName,
                'avatarUrl': data['avatarUrl'],
                'avatarIndex': data['avatarIndex'],
                'role': 'user',
                'timestamp': DateTime.now().millisecondsSinceEpoch,
              });
            } else {
              displayName = otherUser;
            }
          }
        }
      } catch (e) {
        displayName = otherUser; // Show UID as-is on error
      }
      
      data['displayName'] = displayName;
      data['role'] = role;
      enrichedDocs.add(data);
    }
    
    return enrichedDocs;
  }

  Future<List<Map<String, dynamic>>> _fetchEnrichedFriends(String myUid) async {
    final friends = await LocalChatDatabase.instance.getMaleFriends(myUid);
    final enrichedList = <Map<String, dynamic>>[];

    for (var doc in friends) {
      final data = Map<String, dynamic>.from(doc);
      final otherUser = data['otherUid'] as String;
      String displayName = (data['otherUserName'] as String?)?.isNotEmpty == true 
          ? data['otherUserName'] as String 
          : otherUser;
      String? avatarUrl;
      int avatarIndex = 1;

      try {
        final cachedProfile = await LocalChatDatabase.instance.getUserProfile(otherUser);
        if (cachedProfile != null) {
          displayName = cachedProfile['name'] as String? ?? displayName;
          avatarUrl = cachedProfile['avatarUrl'] as String?;
          avatarIndex = (cachedProfile['avatarIndex'] as num?)?.toInt() ?? 1;
        } else {
          final expertData = await UserDatabaseService.instance.getExpert(otherUser);
          if (expertData != null) {
            displayName = expertData['nickname'] ?? expertData['name'] ?? displayName;
            avatarUrl = expertData['profileImageUrl'] ?? expertData['avatarUrl'];
            avatarIndex = (expertData['avatarIndex'] as num?)?.toInt() ?? 1;

            await LocalChatDatabase.instance.saveUserProfile({
              'uid': otherUser,
              'name': displayName,
              'avatarUrl': avatarUrl,
              'avatarIndex': avatarIndex,
              'role': 'expert',
              'timestamp': DateTime.now().millisecondsSinceEpoch,
            });
          }
        }
      } catch (e) {
        // Fallback
      }

      data['displayName'] = displayName;
      data['avatarUrl'] = avatarUrl;
      data['avatarIndex'] = avatarIndex;
      data['role'] = 'expert';
      enrichedList.add(data);
    }

    return enrichedList;
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
        } catch (_) {}

        final expert = FemaleExpert(
          id: expertId,
          nickname: data['nickname'] ?? data['name'] ?? 'Expert',
          pricePerMin: (data['pricePerMin'] as num?)?.toInt() ?? 4,
          languages: data['languages'] ?? 'Hindi',
          rating: (data['rating'] ?? 4.5).toDouble(),
          isOnline: isOnline,
          avatarUrl: data['profileImageUrl'] ?? data['avatarUrl'],
          avatarIndex: (data['avatarIndex'] as num?)?.toInt() ?? 1,
          age: (data['age'] as num?)?.toInt() ?? 22,
        );

        if (!mounted) return;
        final appState = context.read<AppState>();
        final balance = appState.coinBalance;
        const requiredCoins = 40; // ₹4.00

        if (balance < requiredCoins) {
          showDialog(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('Insufficient Balance', style: TextStyle(fontWeight: FontWeight.bold)),
              content: Text('Your balance is ₹${(balance / 10).toStringAsFixed(1)}. You need at least ₹4.0 to place a call.'),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
                ),
                ElevatedButton(
                  onPressed: () {
                    Navigator.pop(context);
                    Navigator.push(context, MaterialPageRoute(builder: (_) => const WalletRechargeScreen()));
                  },
                  style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF4F46E5)),
                  child: const Text('Recharge', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                ),
              ],
            ),
          );
          return;
        }

        // Immediately add/update this female in Friends & Call history
        final now = DateTime.now().millisecondsSinceEpoch;
        LocalChatDatabase.instance.saveCallLogLocally({
          'logId': 'call_${expertId}_$now',
          'callerId': appState.uid,
          'receiverId': expertId,
          'otherUserName': expert.nickname,
          'durationSeconds': 0,
          'status': 'calling',
          'timestamp': now,
          'deductedAmount': 0.0,
        });

        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => MatchmakingScreen(
              requestedExpert: expert,
              isRandomMode: false,
            ),
          ),
        );
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Expert not found')));
        }
      }
    } catch (e) {
      debugPrint('Error triggering call: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    _currentUserMobile = appState.mobileNumber;
    if (_currentUserMobile.isEmpty) _currentUserMobile = "test_mobile";

    final String myUid = appState.uid;
    final bool isCurrentMale = appState.selectedGender != 'Female';
    final bool isFemaleOnline = appState.isOnline;

    if (!isCurrentMale) {
      // ── Female View: FRIENDS and GENERAL Tabs ──
      return Scaffold(
        backgroundColor: AppColors.bgLight,
        body: SafeArea(
          child: Column(
            children: [
              // Top TabBar Header matching exact design
              Container(
                color: Colors.white,
                child: TabBar(
                  controller: _tabController,
                  dividerColor: Colors.transparent,
                  labelColor: const Color(0xFFE11D48),
                  unselectedLabelColor: const Color(0xFF8E8E93),
                  labelStyle: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.4,
                  ),
                  unselectedLabelStyle: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.4,
                  ),
                  indicatorColor: const Color(0xFFE11D48),
                  indicatorWeight: 3.0,
                  indicatorSize: TabBarIndicatorSize.tab,
                  tabs: const [
                    Tab(text: 'FRIENDS'),
                    Tab(text: 'GENERAL'),
                  ],
                ),
              ),

              // Offline Warning Banner for Female Expert
              if (!isFemaleOnline)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: const BoxDecoration(
                    color: Color(0xFFFFF1F2),
                    border: Border(
                      bottom: BorderSide(color: Color(0xFFFECDD3), width: 1),
                    ),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.wifi_off_rounded, color: Color(0xFFE11D48), size: 18),
                      const SizedBox(width: 8),
                      const Expanded(
                        child: Text(
                          "You're offline. Go online to chat & call.",
                          style: TextStyle(
                            color: Color(0xFF9F1239),
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      GestureDetector(
                        onTap: () => _showGoOnlinePrompt(context, appState),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                          decoration: BoxDecoration(
                            color: const Color(0xFFE11D48),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: const Text(
                            'Go Online',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

              // Tab Views
              Expanded(
                child: TabBarView(
                  controller: _tabController,
                  children: [
                    // Tab 1: FRIENDS (Recent chats - only message)
                    _buildFriendsTab(context, appState, myUid, isCurrentMale, isOnline: isFemaleOnline),

                    // Tab 2: GENERAL (Uncalled male users with call & message)
                    _buildGeneralTab(context, appState, myUid, isOnline: isFemaleOnline),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    }

    // ── Male View: Friends (Instant Update on Call or Message with Both Buttons) ──
    return Scaffold(
      backgroundColor: AppColors.bgLight,
      body: SafeArea(
        child: Column(
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
              color: AppColors.bgLight,
              child: const Text(
                'Friends',
                style: TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.w900,
                  color: AppColors.textDark,
                ),
              ),
            ),
            Expanded(
              child: _buildMaleFriendsView(context, appState, myUid),
            ),
          ],
        ),
      ),
    );
  }

  // ─── MALE FRIENDS VIEW (Updated instantly on Call or Message) ────────────

  Widget _buildMaleFriendsView(BuildContext context, AppState appState, String myUid) {
    return StreamBuilder<void>(
      stream: LocalChatDatabase.instance.updates,
      builder: (context, snapshot) {
        return FutureBuilder<List<Map<String, dynamic>>>(
          future: _fetchEnrichedFriends(myUid),
          builder: (context, futureSnapshot) {
            if (futureSnapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator(color: Color(0xFF4F46E5)));
            }

            if (futureSnapshot.hasError) {
              return Center(child: Text('Error loading friends: ${futureSnapshot.error}'));
            }

            final friends = futureSnapshot.data ?? [];
            if (friends.isEmpty) {
              return Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.people_outline_rounded, size: 72, color: Colors.grey.shade400),
                    const SizedBox(height: 16),
                    const Text(
                      'No friends yet.',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: AppColors.textDark,
                      ),
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'Call or message an expert to add them here.',
                      style: TextStyle(fontSize: 14, color: AppColors.textGrey),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              );
            }

            return ListView.builder(
              padding: const EdgeInsets.symmetric(vertical: 10),
              itemCount: friends.length,
              itemBuilder: (context, index) {
                final friend = friends[index];
                final otherUid = friend['otherUid'] as String;
                final displayName = friend['displayName'] as String;
                final avatarUrl = friend['avatarUrl'] as String?;
                final avatarIndex = (friend['avatarIndex'] as num?)?.toInt() ?? 1;
                final timestamp = friend['timestamp'] as int;
                final lastType = friend['lastType'] as String? ?? 'call';
                final lastText = friend['lastText'] as String? ?? '';
                final unreadCount = (friend['unreadCount'] as num?)?.toInt() ?? 0;

                final dt = DateTime.fromMillisecondsSinceEpoch(timestamp);
                final now = DateTime.now();
                String timeText;
                if (dt.year == now.year && dt.month == now.month && dt.day == now.day) {
                  timeText = TimeOfDay.fromDateTime(dt).format(context);
                } else {
                  timeText = '${dt.day}/${dt.month}';
                }

                return _buildMaleFriendCard(
                  uid: otherUid,
                  name: displayName,
                  avatarUrl: avatarUrl,
                  avatarIndex: avatarIndex,
                  lastType: lastType,
                  lastText: lastText,
                  timeText: timeText,
                  unreadCount: unreadCount,
                  onCallTap: () => _triggerCallByExpertId(otherUid),
                  onMessageTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => HybridChatScreen(
                          myUid: myUid,
                          otherUid: otherUid,
                          otherUserName: displayName,
                          otherUserAvatarUrl: avatarUrl,
                          otherUserAvatarIndex: avatarIndex,
                        ),
                      ),
                    );
                  },
                );
              },
            );
          },
        );
      },
    );
  }

  // ─── MALE FRIEND CARD (Both Call and Message Buttons) ───────────────────

  Widget _buildMaleFriendCard({
    required String uid,
    required String name,
    required String? avatarUrl,
    required int avatarIndex,
    required String lastType,
    required String lastText,
    required String timeText,
    required int unreadCount,
    required VoidCallback onCallTap,
    required VoidCallback onMessageTap,
  }) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: const Color(0xFFE2E8F0),
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: InkWell(
        onTap: onMessageTap,
        borderRadius: BorderRadius.circular(20),
        child: Row(
          children: [
            // Avatar
            LocalAvatarWidget(
              uid: uid,
              role: 'expert',
              radius: 26,
              avatarIndex: avatarIndex,
              avatarUrl: avatarUrl,
            ),
            const SizedBox(width: 12),

            // Name and Last Interaction
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    name,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: AppColors.textDark,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 3),
                  Row(
                    children: [
                      Icon(
                        lastType == 'call' ? Icons.phone_in_talk_rounded : Icons.chat_bubble_outline_rounded,
                        size: 13,
                        color: lastType == 'call' ? const Color(0xFF10B981) : const Color(0xFF4F46E5),
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          lastType == 'call'
                              ? 'Call • $lastText • $timeText'
                              : '$lastText • $timeText',
                          style: TextStyle(
                            fontSize: 12.5,
                            color: unreadCount > 0 ? AppColors.textDark : AppColors.textGrey,
                            fontWeight: unreadCount > 0 ? FontWeight.bold : FontWeight.w500,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),

            // Action Buttons: BOTH Call and Message
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Call Button
                GestureDetector(
                  onTap: onCallTap,
                  child: Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: const Color(0xFF4F46E5), // Indigo
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF4F46E5).withValues(alpha: 0.25),
                          blurRadius: 6,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.phone_in_talk_rounded,
                      color: Colors.white,
                      size: 18,
                    ),
                  ),
                ),
                const SizedBox(width: 8),

                // Message Button
                GestureDetector(
                  onTap: onMessageTap,
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Container(
                        width: 38,
                        height: 38,
                        decoration: BoxDecoration(
                          color: const Color(0xFFE11D48), // Rose
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFFE11D48).withValues(alpha: 0.25),
                              blurRadius: 6,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: const Icon(
                          Icons.chat_bubble_rounded,
                          color: Colors.white,
                          size: 18,
                        ),
                      ),
                      if (unreadCount > 0)
                        Positioned(
                          top: -4,
                          right: -4,
                          child: Container(
                            padding: const EdgeInsets.all(4),
                            decoration: const BoxDecoration(
                              color: Colors.red,
                              shape: BoxShape.circle,
                            ),
                            constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
                            child: Center(
                              child: Text(
                                unreadCount > 99 ? '99+' : unreadCount.toString(),
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 9,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ─── TAB 1: FRIENDS (Only Messages) ──────────────────────────────────────

  Widget _buildFriendsTab(
    BuildContext context,
    AppState appState,
    String myUid,
    bool isCurrentMale, {
    required bool isOnline,
  }) {
    return StreamBuilder<void>(
      stream: LocalChatDatabase.instance.updates,
      builder: (context, snapshot) {
        return FutureBuilder<List<Map<String, dynamic>>>(
          future: _fetchEnrichedChats(myUid, isCurrentMale),
          builder: (context, futureSnapshot) {
            if (futureSnapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator(color: Color(0xFFE11D48)));
            }

            if (futureSnapshot.hasError) {
              return Center(child: Text('Error loading chats: ${futureSnapshot.error}'));
            }

            final chatDocs = futureSnapshot.data ?? [];
            if (chatDocs.isEmpty) {
              return _buildEmptyState();
            }

            // Pinned chats appear first
            chatDocs.sort((a, b) {
              final aPinned = _pinnedUids.contains(a['otherUserId']);
              final bPinned = _pinnedUids.contains(b['otherUserId']);
              if (aPinned && !bPinned) return -1;
              if (!aPinned && bPinned) return 1;
              return 0;
            });

            return ListView.builder(
              padding: const EdgeInsets.symmetric(vertical: 12),
              itemCount: chatDocs.length,
              itemBuilder: (context, index) {
                final data = chatDocs[index];
                final otherUser = data['otherUserId'] as String;
                final lastMessage = data['lastMessage'] as String;
                final timestamp = data['timestamp'] as int;
                final unreadCount = data['unreadCount'] as int;
                final displayName = data['displayName'] as String;
                final dt = DateTime.fromMillisecondsSinceEpoch(timestamp);
                final now = DateTime.now();
                String dayText;
                if (dt.year == now.year && dt.month == now.month && dt.day == now.day) {
                  dayText = TimeOfDay.fromDateTime(dt).format(context);
                } else {
                  dayText = '${dt.day}/${dt.month}';
                }

                final role = data['role'] as String? ?? 'user';

                return _buildFriendChatCard(
                  uid: otherUser,
                  role: role,
                  name: displayName,
                  subtitle: lastMessage.isNotEmpty ? lastMessage : 'Tap to open chat',
                  trailingText: dayText,
                  unreadCount: unreadCount,
                  avatarUrl: data['avatarUrl'] as String?,
                  avatarIndex: (data['avatarIndex'] as num?)?.toInt() ?? 1,
                  isOnline: isOnline,
                  onDisabledTap: () => _showGoOnlinePrompt(context, appState),
                  onMessageTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => HybridChatScreen(
                          myUid: myUid,
                          otherUid: otherUser,
                          otherUserName: displayName,
                          otherUserAvatarUrl: data['avatarUrl'] as String?,
                          otherUserAvatarIndex: (data['avatarIndex'] as num?)?.toInt() ?? 1,
                        ),
                      ),
                    );
                  },
                );
              },
            );
          },
        );
      },
    );
  }

  // ─── TAB 2: GENERAL (Uncalled Male Users) ─────────────────────────────────

  Widget _buildGeneralTab(
    BuildContext context,
    AppState appState,
    String myUid, {
    required bool isOnline,
  }) {
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: _newMalesStream,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting && !snapshot.hasData) {
          return const Center(
            child: CircularProgressIndicator(color: Color(0xFFE11D48)),
          );
        }

              final users = snapshot.data ?? [];
              if (users.isEmpty) {
                return RefreshIndicator(
                  color: const Color(0xFFE11D48),
                  onRefresh: () async => _refreshNewMales(appState.primaryLanguage),
                  child: ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    children: [
                      const SizedBox(height: 70),
                      Center(
                        child: Column(
                          children: [
                            Icon(Icons.person_search_rounded, size: 64, color: Colors.grey.shade400),
                            const SizedBox(height: 12),
                            const Text(
                              'No new male users right now.',
                              style: TextStyle(
                                fontSize: 16,
                                color: AppColors.textGrey,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 6),
                            const Text(
                              'Pull down to refresh',
                              style: TextStyle(fontSize: 13, color: Colors.grey),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              }

              return RefreshIndicator(
                color: const Color(0xFFE11D48),
                onRefresh: () async => _refreshNewMales(appState.primaryLanguage),
                child: ListView.builder(
                  padding: const EdgeInsets.only(top: 8, bottom: 24),
                  physics: const AlwaysScrollableScrollPhysics(),
                  itemCount: users.length,
                  itemBuilder: (context, index) {
                    final user = users[index];
                    final targetUid = user['uid'] as String? ?? '';
                    final nickname = user['nickname'] as String? ?? 'User';
                    final avatarUrl = user['avatarUrl'] as String?;
                    final avatarIndex = (user['avatarIndex'] as num?)?.toInt() ?? 1;
                    final userLang = user['language'] as String? ?? 'Hindi';

                    return _buildModernChatCard(
                      uid: targetUid,
                      role: 'user',
                      name: nickname,
                      subtitle: 'Available for call • $userLang',
                      trailingText: '1m Free',
                      unreadCount: 0,
                      avatarUrl: avatarUrl,
                      avatarIndex: avatarIndex,
                      showCallButton: true, // In general show BOTH call and message button
                      isOnline: isOnline,
                      onDisabledTap: () => _showGoOnlinePrompt(context, appState),
                      onCallTap: () => _startIntroCall(appState, user),
                      onMessageTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => HybridChatScreen(
                              myUid: myUid,
                              otherUid: targetUid,
                              otherUserName: nickname,
                              otherUserAvatarUrl: avatarUrl,
                              otherUserAvatarIndex: avatarIndex,
                            ),
                          ),
                        );
                      },
                    );
                  },
                ),
              );
            },
          );
  }

  // ─── FRIENDS CARD DESIGN (Single-Line Modern Design) ─────────────────────

  Widget _buildFriendChatCard({
    required String uid,
    required String role,
    required String name,
    required String subtitle,
    required String trailingText,
    required int unreadCount,
    String? avatarUrl,
    int? avatarIndex,
    bool isOnline = true,
    VoidCallback? onDisabledTap,
    required VoidCallback onMessageTap,
  }) {
    final isPinned = _pinnedUids.contains(uid);

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isPinned ? const Color(0xFFE11D48).withValues(alpha: 0.35) : const Color(0xFFE2E8F0),
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: InkWell(
        onTap: isOnline ? onMessageTap : onDisabledTap,
        borderRadius: BorderRadius.circular(20),
        child: Row(
          children: [
            // Avatar
            LocalAvatarWidget(
              uid: uid,
              role: role,
              radius: 26,
              avatarIndex: avatarIndex ?? 1,
              avatarUrl: avatarUrl,
            ),
            const SizedBox(width: 12),

            // Name and Last Message
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    name,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: AppColors.textDark,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 3),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 13,
                      color: unreadCount > 0 ? AppColors.textDark : AppColors.textGrey,
                      fontWeight: unreadCount > 0 ? FontWeight.bold : FontWeight.w500,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),

            // Time / Badge
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  trailingText,
                  style: const TextStyle(
                    fontSize: 11.5,
                    color: Color(0xFF94A3B8),
                    fontWeight: FontWeight.w500,
                  ),
                ),
                if (unreadCount > 0) ...[
                  const SizedBox(height: 4),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                    decoration: const BoxDecoration(
                      color: Color(0xFFE11D48),
                      shape: BoxShape.circle,
                    ),
                    child: Text(
                      unreadCount.toString(),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ],
            ),

            const SizedBox(width: 10),

            // Blue Message Button on the same single line!
            Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: isOnline ? onMessageTap : onDisabledTap,
                borderRadius: BorderRadius.circular(16),
                child: Ink(
                  height: 40,
                  width: 40,
                  decoration: BoxDecoration(
                    gradient: isOnline
                        ? const LinearGradient(
                            colors: [Color(0xFF3B82F6), Color(0xFF2563EB)],
                            begin: Alignment.centerLeft,
                            end: Alignment.centerRight,
                          )
                        : const LinearGradient(
                            colors: [Color(0xFFE2E8F0), Color(0xFFCBD5E1)],
                            begin: Alignment.centerLeft,
                            end: Alignment.centerRight,
                          ),
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: isOnline
                        ? [
                            BoxShadow(
                              color: const Color(0xFF3B82F6).withValues(alpha: 0.35),
                              blurRadius: 6,
                              offset: const Offset(0, 2),
                            ),
                          ]
                        : [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.04),
                              blurRadius: 4,
                              offset: const Offset(0, 2),
                            ),
                          ],
                  ),
                  child: Center(
                    child: Icon(
                      Icons.chat_bubble_rounded,
                      color: isOnline ? Colors.white : const Color(0xFF94A3B8),
                      size: 19,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─── GENERAL CARD DESIGN (Matching user uploaded image) ──────────────────

  Widget _buildModernChatCard({
    required String uid,
    required String role,
    required String name,
    required String subtitle,
    required String trailingText,
    required int unreadCount,
    String? avatarUrl,
    int? avatarIndex,
    required bool showCallButton,
    bool isOnline = true,
    VoidCallback? onDisabledTap,
    required VoidCallback onMessageTap,
    VoidCallback? onCallTap,
  }) {
    final isPinned = _pinnedUids.contains(uid);

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isPinned ? const Color(0xFFE11D48).withValues(alpha: 0.35) : const Color(0xFFE2E8F0),
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: InkWell(
        onTap: isOnline ? onMessageTap : onDisabledTap,
        borderRadius: BorderRadius.circular(20),
        child: Row(
          children: [
            // Avatar
            LocalAvatarWidget(
              uid: uid,
              role: role,
              radius: 26,
              avatarIndex: avatarIndex ?? 1,
              avatarUrl: avatarUrl,
            ),
            const SizedBox(width: 12),

            // Name and Subtitle
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    name,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: AppColors.textDark,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 3),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 12.5,
                      color: unreadCount > 0 ? AppColors.textDark : AppColors.textGrey,
                      fontWeight: unreadCount > 0 ? FontWeight.bold : FontWeight.w500,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),

            // Time / Badge (if any)
            if (trailingText.isNotEmpty || unreadCount > 0) ...[
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (trailingText.isNotEmpty)
                    Text(
                      trailingText,
                      style: const TextStyle(
                        fontSize: 11.5,
                        color: Color(0xFF94A3B8),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  if (unreadCount > 0) ...[
                    const SizedBox(height: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                      decoration: const BoxDecoration(
                        color: Color(0xFFE11D48),
                        shape: BoxShape.circle,
                      ),
                      child: Text(
                        unreadCount.toString(),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(width: 8),
            ],

            // Green Call Button (if showCallButton)
            if (showCallButton && onCallTap != null) ...[
              Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: isOnline ? onCallTap : onDisabledTap,
                  borderRadius: BorderRadius.circular(16),
                  child: Ink(
                    height: 38,
                    width: 38,
                    decoration: BoxDecoration(
                      gradient: isOnline
                          ? const LinearGradient(
                              colors: [Color(0xFF10B981), Color(0xFF059669)],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            )
                          : const LinearGradient(
                              colors: [Color(0xFFE2E8F0), Color(0xFFCBD5E1)],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: isOnline
                          ? [
                              BoxShadow(
                                color: const Color(0xFF10B981).withValues(alpha: 0.35),
                                blurRadius: 6,
                                offset: const Offset(0, 2),
                              ),
                            ]
                          : null,
                    ),
                    child: Center(
                      child: Icon(
                        Icons.call_rounded,
                        color: isOnline ? Colors.white : const Color(0xFF94A3B8),
                        size: 19,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
            ],

            // Blue Message Button
            Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: isOnline ? onMessageTap : onDisabledTap,
                borderRadius: BorderRadius.circular(16),
                child: Ink(
                  height: 38,
                  width: 38,
                  decoration: BoxDecoration(
                    gradient: isOnline
                        ? const LinearGradient(
                            colors: [Color(0xFF3B82F6), Color(0xFF2563EB)],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          )
                        : const LinearGradient(
                            colors: [Color(0xFFE2E8F0), Color(0xFFCBD5E1)],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: isOnline
                        ? [
                            BoxShadow(
                              color: const Color(0xFF3B82F6).withValues(alpha: 0.35),
                              blurRadius: 6,
                              offset: const Offset(0, 2),
                            ),
                          ]
                        : null,
                  ),
                  child: Center(
                    child: Icon(
                      Icons.chat_bubble_rounded,
                      color: isOnline ? Colors.white : const Color(0xFF94A3B8),
                      size: 18,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─── PROMPT & GO ONLINE HANDLERS ─────────────────────────────────────────

  Future<void> _handleGoOnline(AppState appState) async {
    // 1. Check Notifications Permission
    final hasNotif = await Permission.notification.request().isGranted;
    if (!hasNotif) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Notifications permission is required to receive calls.')),
        );
      }
      return;
    }

    // 2. Check System Alert Window (Display over other apps)
    final hasAlert = await Permission.systemAlertWindow.request().isGranted;
    if (!hasAlert) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Display over other apps permission is required for incoming calls.')),
        );
      }
      return;
    }

    // 3. Check Microphone Permission
    final micStatus = await Permission.microphone.status;
    bool hasMic = micStatus.isGranted;
    if (!hasMic) {
      final req = await Permission.microphone.request();
      hasMic = req.isGranted;
    }
    if (!hasMic) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Microphone permission is required to talk on calls.')),
        );
      }
      return;
    }

    if (!mounted) return;
    appState.setOnlineStatus(true);

    final String expertId = appState.uid;
    debugPrint('[STATUS] ChatList going online: expertId=$expertId');
    if (expertId.isNotEmpty) {
      try {
        await _matchingService.setExpertOnlineStatus(
          expertId: expertId,
          isOnline: true,
          gender: 'female',
          language: appState.primaryLanguage,
        );
        await UserDatabaseService.instance.updateExpert(expertId, {
          'nickname': appState.nickname,
          'mobileNumber': appState.mobileNumber,
          'age': 2026 - appState.birthYear,
          'pricePerMin': 4,
          'languages': appState.primaryLanguage,
          'rating': 4.8,
        });
        await UserDatabaseService.instance.joinExpertBucket(expertId, appState.primaryLanguage);
        debugPrint('[STATUS] ChatList successfully joined expert bucket and online queue');
      } catch (e) {
        debugPrint('[STATUS] Error going online from ChatList: $e');
      }

      try {
        ForegroundTaskService.startService();
      } catch (e) {
        debugPrint('[STATUS] Error starting ForegroundTaskService: $e');
      }
    }

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Row(
            children: [
              Icon(Icons.check_circle_rounded, color: Colors.greenAccent),
              SizedBox(width: 8),
              Text('You are now Online! 🟢 Chat & Calls enabled.'),
            ],
          ),
          backgroundColor: Color(0xFF1E293B),
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  void _showGoOnlinePrompt(BuildContext context, AppState appState) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (bottomSheetContext) {
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.only(
              topLeft: Radius.circular(28),
              topRight: Radius.circular(28),
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Pull Handle
              Container(
                width: 44,
                height: 5,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              const SizedBox(height: 20),

              // Glowing Offline Icon
              Container(
                width: 70,
                height: 70,
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF1F2),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: const Color(0xFFFECDD3),
                    width: 2,
                  ),
                ),
                child: const Center(
                  child: Icon(
                    Icons.power_settings_new_rounded,
                    color: Color(0xFFE11D48),
                    size: 36,
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // Title
              const Text(
                "You're Currently Offline",
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textDark,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),

              // Description
              const Text(
                "Please go online to start messaging, making intro calls, and talking to users.",
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  color: AppColors.textGrey,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 20),

              // Benefit perks container
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: const Column(
                  children: [
                    Row(
                      children: [
                        Icon(Icons.mark_chat_unread_rounded, size: 18, color: Color(0xFF10B981)),
                        SizedBox(width: 10),
                        Text('Chat & reply to user messages', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textDark)),
                      ],
                    ),
                    SizedBox(height: 10),
                    Row(
                      children: [
                        Icon(Icons.call_rounded, size: 18, color: Color(0xFFA855F7)),
                        SizedBox(width: 10),
                        Text('1-minute free intro & incoming calls', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textDark)),
                      ],
                    ),
                    SizedBox(height: 10),
                    Row(
                      children: [
                        Icon(Icons.monetization_on_rounded, size: 18, color: Color(0xFFF59E0B)),
                        SizedBox(width: 10),
                        Text('Earn real money on every call minute', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textDark)),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              // Primary "Go Online Now" CTA Button
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  onPressed: () async {
                    Navigator.pop(bottomSheetContext);
                    await _handleGoOnline(appState);
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFE11D48),
                    foregroundColor: Colors.white,
                    elevation: 3,
                    shadowColor: const Color(0xFFE11D48).withValues(alpha: 0.35),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(25),
                    ),
                  ),
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.flash_on_rounded, size: 20),
                      SizedBox(width: 8),
                      Text(
                        'Go Online Now',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 10),

              // Dismiss Button
              TextButton(
                onPressed: () => Navigator.pop(bottomSheetContext),
                child: const Text(
                  'Stay Offline',
                  style: TextStyle(
                    color: Color(0xFF94A3B8),
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildEmptyState() {
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.chat_bubble_outline, size: 64, color: AppColors.textGrey),
          SizedBox(height: 16),
          Text(
            'No active chats.',
            style: TextStyle(fontSize: 18, color: AppColors.textGrey),
          ),
        ],
      ),
    );
  }

  Future<void> _startIntroCall(
    AppState appState,
    Map<String, dynamic> maleUser,
  ) async {
    if (_isCallingUser) return;
    final status = await Permission.microphone.request();
    if (!status.isGranted) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Microphone permission required for calling.')),
      );
      return;
    }

    setState(() => _isCallingUser = true);
    final targetUid = maleUser['uid'] as String;
    final nickname = maleUser['nickname'] as String? ?? 'User';
    final avatarUrl = maleUser['avatarUrl'] as String?;
    final avatarIndex = (maleUser['avatarIndex'] as num?)?.toInt() ?? 1;

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
            ),
            const SizedBox(width: 12),
            Text('Calling $nickname (1-Min Free Intro)...'),
          ],
        ),
        duration: const Duration(seconds: 4),
      ),
    );

    try {
      String receiverFcmToken = '';
      try {
        final tokenSnap = await NewMaleService.instance.maleUsersRef.child(targetUid).child('fcmToken').get();
        if (tokenSnap.exists && tokenSnap.value != null && tokenSnap.value.toString().isNotEmpty) {
          receiverFcmToken = tokenSnap.value.toString();
        } else {
          final poolTokenSnap = await NewMaleService.instance.newMalesPoolRef.child(targetUid).child('fcmToken').get();
          if (poolTokenSnap.exists && poolTokenSnap.value != null && poolTokenSnap.value.toString().isNotEmpty) {
            receiverFcmToken = poolTokenSnap.value.toString();
          }
        }
      } catch (e) {
        debugPrint('[ChatList] Error fetching fresh FCM token for $targetUid: $e');
      }

      if (receiverFcmToken.isEmpty) {
        receiverFcmToken = (maleUser['fcmToken'] as String?) ?? '';
      }

      // Fallback to Firestore users collection if still empty
      if (receiverFcmToken.isEmpty) {
        try {
          final uDoc = await FirebaseFirestore.instance.collection('users').doc(targetUid).get();
          if (uDoc.exists && uDoc.data() != null) {
            final fToken = uDoc.data()!['fcmToken'] as String?;
            if (fToken != null && fToken.isNotEmpty) {
              receiverFcmToken = fToken;
              // Sync back to 1e689 RTDB
              NewMaleService.instance.maleUsersRef.child(targetUid).child('fcmToken').set(fToken).catchError((_) {});
            }
          }
        } catch (_) {}
      }

      // Temporarily mark target male as busy so other females don't call him simultaneously
      NewMaleService.instance.newMalesPoolRef.child(targetUid).update({
        'callStatus': 'busy',
        'busyAt': ServerValue.timestamp,
      }).catchError((_) {});

      final callService = CallService(databaseURL: NewMaleService.newDbUrl);
      final roomId = await callService.startCall(
        expertId: targetUid,
        callerId: appState.uid,
        callerCoins: 0,
        pricePerMin: 0.0,
        extraRoomData: {
          'isFreeIntroCall': true,
          'maxDurationSeconds': 60,
          'callerName': appState.nickname.isNotEmpty ? appState.nickname : 'Female Expert',
          'callerAvatar': 'assets/avatars/female_${appState.avatarIndex}.png',
          'callerAvatarIndex': appState.avatarIndex,
          'callerLanguage': appState.primaryLanguage.isNotEmpty ? appState.primaryLanguage : 'Hindi',
          'receiverLanguage': maleUser['language'] ?? 'Hindi',
          'receiverFcmToken': receiverFcmToken,
          'dbUrl': NewMaleService.newDbUrl,
        },
        onRemoteStream: (_) {},
        onCallEnded: () {},
      );

      if (!mounted) return;
      setState(() => _isCallingUser = false);
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ActiveCallPage(
            callRoomId: roomId,
            receiverId: targetUid,
            callerId: appState.uid,
            nickname: nickname,
            avatarUrl: avatarUrl,
            avatarIndex: avatarIndex,
            pricePerMin: 0.0,
            isCaller: true,
            preStartedCallService: callService,
            callDatabaseURL: NewMaleService.newDbUrl,
            isFreeIntroCall: true,
            maxDurationSeconds: 60,
            callerLanguage: appState.primaryLanguage.isNotEmpty ? appState.primaryLanguage : 'Hindi',
          ),
        ),
      );
    } catch (e) {
      debugPrint('[ChatList] Error starting intro call: $e');
      if (!mounted) return;
      setState(() => _isCallingUser = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to place call: $e')),
      );
    }
  }

}
