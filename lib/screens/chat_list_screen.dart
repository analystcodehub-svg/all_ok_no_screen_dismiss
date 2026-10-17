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
import '../services/block_service.dart';
import 'active_call_page.dart';

class ChatListScreen extends StatefulWidget {
  const ChatListScreen({super.key});

  @override
  State<ChatListScreen> createState() => _ChatListScreenState();
}

class _ChatListScreenState extends State<ChatListScreen> {
  late String _currentUserMobile;
  Future<List<Map<String, dynamic>>>? _newMalesFuture;
  bool _isCallingUser = false;

  @override
  void initState() {
    super.initState();
    final appState = context.read<AppState>();
    _refreshNewMales(appState.primaryLanguage);
  }

  void _refreshNewMales([String? lang]) {
    final appState = context.read<AppState>();
    final effectiveLang = lang ?? appState.primaryLanguage;
    _newMalesFuture = NewMaleService.instance.fetchNewMalesWithFallback(
      femaleLanguage: effectiveLang.isNotEmpty ? effectiveLang : 'Hindi',
      limit: 20,
    );
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

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    _currentUserMobile = appState.mobileNumber;
    if (_currentUserMobile.isEmpty) _currentUserMobile = "test_mobile";

    final String myUid = appState.uid;

    // Determine if current user is male
    bool isCurrentMale = appState.selectedGender != 'Female';

    return Scaffold(
      backgroundColor: AppColors.bgLight,
      body: SafeArea(
        child: Column(
          children: [
            // Left-aligned Large Header matching Recents
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 10.0),
              color: AppColors.bgLight,
              child: const Text(
                'Chats',
                style: TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.w900,
                  color: AppColors.textDark,
                ),
              ),
            ),
            if (!isCurrentMale)
              _buildNewMaleUsersSection(context, appState),
            // List View connected to Local SQLite
            Expanded(
              child: StreamBuilder<void>(
                // Listen to local DB updates so inbox refreshes automatically
                stream: LocalChatDatabase.instance.updates,
                builder: (context, snapshot) {
                  return FutureBuilder<List<Map<String, dynamic>>>(
                    future: _fetchEnrichedChats(myUid, isCurrentMale),
                    builder: (context, futureSnapshot) {
                      if (futureSnapshot.connectionState == ConnectionState.waiting) {
                        return const Center(child: CircularProgressIndicator());
                      }

                      if (futureSnapshot.hasError) {
                        return Center(child: Text('Error loading chats: ${futureSnapshot.error}'));
                      }

                      final chatDocs = futureSnapshot.data ?? [];
                      if (chatDocs.isEmpty) {
                        return _buildEmptyState();
                      }

                      return ListView.builder(
                        padding: const EdgeInsets.all(20),
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

                          return _buildChatCard(
                            uid: otherUser,
                            role: role,
                            name: displayName,
                            lastMessage: lastMessage,
                            dayText: dayText,
                            unreadCount: unreadCount,
                            avatarUrl: data['avatarUrl'] as String?,
                            avatarIndex: (data['avatarIndex'] as num?)?.toInt() ?? 1,
                            onTap: () {
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
              ),
            ),
          ],
        ),
      ),
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

  Widget _buildChatCard({
    required String uid,
    required String role,
    required String name,
    required String lastMessage,
    required String dayText,
    required int unreadCount,
    required VoidCallback onTap,
    String? avatarUrl,
    int? avatarIndex,
  }) {

    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 16),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.cardWhite,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 10,
              spreadRadius: 1,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: [
            LocalAvatarWidget(
              uid: uid,
              role: role,
              radius: 26,
              avatarIndex: avatarIndex ?? 1,
              avatarUrl: avatarUrl,
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: AppColors.textDark,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    lastMessage,
                    style: TextStyle(
                      fontSize: 14,
                      color: unreadCount > 0 ? AppColors.textDark : AppColors.textGrey,
                      fontWeight: unreadCount > 0 ? FontWeight.bold : FontWeight.normal,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  dayText,
                  style: TextStyle(
                    fontSize: 12,
                    color: unreadCount > 0 ? AppColors.primaryBlue : AppColors.textGrey,
                    fontWeight: unreadCount > 0 ? FontWeight.bold : FontWeight.normal,
                  ),
                ),
                const SizedBox(height: 8),
                if (unreadCount > 0)
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: const BoxDecoration(
                      color: AppColors.primaryBlue,
                      shape: BoxShape.circle,
                    ),
                    child: Text(
                      unreadCount.toString(),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNewMaleUsersSection(BuildContext context, AppState appState) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 2, 16, 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFE4E6),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.person_pin_rounded, color: Color(0xFFE11D48), size: 18),
                  ),
                  const SizedBox(width: 8),
                  const Text(
                    'New Users',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: AppColors.textDark,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                    decoration: BoxDecoration(
                      color: const Color(0xFFDCFCE7),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Text(
                      '1-Min Free',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF166534),
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                    decoration: BoxDecoration(
                      color: const Color(0xFFEFF6FF),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: const Color(0xFFDBEAFE)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.language_rounded, size: 10, color: Color(0xFF2563EB)),
                        const SizedBox(width: 3),
                        Text(
                          appState.primaryLanguage.isNotEmpty ? appState.primaryLanguage : 'All',
                          style: const TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF2563EB),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              InkWell(
                onTap: () => _handleRandomCall(context, appState),
                borderRadius: BorderRadius.circular(20),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFFE11D48), Color(0xFFF43F5E)],
                    ),
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFFF43F5E).withValues(alpha: 0.3),
                        blurRadius: 6,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.shuffle_rounded, color: Colors.white, size: 14),
                      SizedBox(width: 5),
                      Text(
                        'Random Call',
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
          const SizedBox(height: 10),
          SizedBox(
            height: 104,
            child: FutureBuilder<List<Map<String, dynamic>>>(
              future: _newMalesFuture,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return ListView.builder(
                    scrollDirection: Axis.horizontal,
                    itemCount: 5,
                    itemBuilder: (context, index) => Padding(
                      padding: const EdgeInsets.only(right: 12),
                      child: Column(
                        children: [
                          Container(
                            width: 50,
                            height: 50,
                            decoration: BoxDecoration(
                              color: Colors.grey.shade200,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Container(
                            width: 42,
                            height: 8,
                            decoration: BoxDecoration(
                              color: Colors.grey.shade200,
                              borderRadius: BorderRadius.circular(4),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }

                final users = snapshot.data ?? [];
                if (users.isEmpty) {
                  return const Center(
                    child: Text(
                      'No new users available right now.',
                      style: TextStyle(fontSize: 12, color: AppColors.textGrey),
                    ),
                  );
                }

                return ListView.builder(
                  scrollDirection: Axis.horizontal,
                  physics: const BouncingScrollPhysics(),
                  itemCount: users.length > 20 ? 20 : users.length,
                  itemBuilder: (context, index) {
                    final user = users[index];
                    final nickname = user['nickname'] as String? ?? 'User';
                    final avatarUrl = user['avatarUrl'] as String?;
                    final avatarIndex = (user['avatarIndex'] as num?)?.toInt() ?? 1;

                    return Padding(
                      padding: const EdgeInsets.only(right: 14),
                      child: InkWell(
                        onTap: () => _startIntroCall(context, appState, user),
                        borderRadius: BorderRadius.circular(16),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Stack(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(2),
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: const Color(0xFFF43F5E),
                                      width: 1.8,
                                    ),
                                  ),
                                  child: LocalAvatarWidget(
                                    uid: user['uid'] ?? '',
                                    role: 'user',
                                    radius: 23,
                                    avatarIndex: avatarIndex,
                                    avatarUrl: avatarUrl,
                                  ),
                                ),
                                Positioned(
                                  bottom: 0,
                                  right: 0,
                                  child: Container(
                                    padding: const EdgeInsets.all(3),
                                    decoration: const BoxDecoration(
                                      color: Color(0xFF10B981),
                                      shape: BoxShape.circle,
                                    ),
                                    child: const Icon(
                                      Icons.call,
                                      size: 10,
                                      color: Colors.white,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 5),
                            SizedBox(
                              width: 62,
                              child: Text(
                                nickname,
                                textAlign: TextAlign.center,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.textDark,
                                ),
                              ),
                            ),
                            const SizedBox(height: 2),
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFEFF6FF),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    user['language'] as String? ?? 'Hindi',
                                    style: const TextStyle(
                                      fontSize: 8,
                                      color: Color(0xFF2563EB),
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 3),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFF3F4F6),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: const Text(
                                    '1m',
                                    style: TextStyle(
                                      fontSize: 8,
                                      color: Color(0xFF6B7280),
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
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

  Future<void> _startIntroCall(
    BuildContext context,
    AppState appState,
    Map<String, dynamic> maleUser,
  ) async {
    if (_isCallingUser) return;
    final status = await Permission.microphone.request();
    if (!status.isGranted) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Microphone permission required for calling.')),
        );
      }
      return;
    }

    setState(() => _isCallingUser = true);
    final targetUid = maleUser['uid'] as String;
    final nickname = maleUser['nickname'] as String? ?? 'User';
    final avatarUrl = maleUser['avatarUrl'] as String?;
    final avatarIndex = (maleUser['avatarIndex'] as num?)?.toInt() ?? 1;

    if (mounted) {
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
    }

    try {
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
          'receiverFcmToken': maleUser['fcmToken'] ?? '',
          'dbUrl': NewMaleService.newDbUrl,
        },
        onRemoteStream: (_) {},
        onCallEnded: () {},
      );

      if (mounted) {
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
            ),
          ),
        );
      }
    } catch (e) {
      debugPrint('[ChatList] Error starting intro call: $e');
      if (mounted) {
        setState(() => _isCallingUser = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to place call: $e')),
        );
      }
    }
  }

  Future<void> _handleRandomCall(BuildContext context, AppState appState) async {
    if (_isCallingUser) return;
    final status = await Permission.microphone.request();
    if (!status.isGranted) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Microphone permission required for calling.')),
        );
      }
      return;
    }

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogCtx) {
        return Dialog(
          backgroundColor: Colors.transparent,
          elevation: 0,
          child: Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(24),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.15),
                  blurRadius: 20,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: const BoxDecoration(
                    color: Color(0xFFFEE2E2),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.shuffle_rounded, color: Color(0xFFE11D48), size: 36),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Random Matchmaking',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                    color: AppColors.textDark,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Connecting you with an active user speaking ${appState.primaryLanguage.isNotEmpty ? appState.primaryLanguage : 'your language'} for a 1-minute intro call...',
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 13, color: AppColors.textGrey),
                ),
                const SizedBox(height: 20),
                const CircularProgressIndicator(color: Color(0xFFE11D48)),
                const SizedBox(height: 16),
                TextButton(
                  onPressed: () => Navigator.pop(dialogCtx),
                  child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
                ),
              ],
            ),
          ),
        );
      },
    );

    try {
      final blocked = BlockService.instance.blockedUids;
      final femaleLang = appState.primaryLanguage.isNotEmpty ? appState.primaryLanguage : 'Hindi';
      final randomMale = await NewMaleService.instance.pickRandomMale(
        blocked,
        femaleLanguage: femaleLang,
      );
      if (!mounted) return;
      Navigator.of(context, rootNavigator: true).pop(); // Dismiss search dialog

      if (randomMale == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No new users available at the moment. Please try again soon!')),
        );
        return;
      }

      await _startIntroCall(context, appState, randomMale);
    } catch (e) {
      if (mounted) {
        Navigator.of(context, rootNavigator: true).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Matchmaking error: $e')),
        );
      }
    }
  }
}
