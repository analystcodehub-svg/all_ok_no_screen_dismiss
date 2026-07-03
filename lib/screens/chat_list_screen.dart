import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../theme/app_colors.dart';
import '../providers/app_state.dart';
import '../services/local_chat_database.dart';
import 'hybrid_chat_screen.dart';

class ChatListScreen extends StatefulWidget {
  const ChatListScreen({super.key});

  @override
  State<ChatListScreen> createState() => _ChatListScreenState();
}

class _ChatListScreenState extends State<ChatListScreen> {
  int _selectedTab = 0; // 0 for FRIENDS, 1 for GENERAL
  late String _currentUserMobile;

  @override
  void initState() {
    super.initState();
    // We defer getting the current user mobile to build() using Provider, 
    // but we can initialize data fetching here if needed.
  }

  Future<List<Map<String, dynamic>>> _fetchEnrichedChats(String myUid) async {
    final chatDocs = await LocalChatDatabase.instance.getRecentChats(myUid);
    final enrichedDocs = <Map<String, dynamic>>[];

    for (var doc in chatDocs) {
      final data = Map<String, dynamic>.from(doc);
      final otherUser = data['otherUserId'] as String;
      
      String displayName = otherUser;
      if (RegExp(r'^\+?[0-9]{10,15}$').hasMatch(otherUser)) {
        try {
          final userDoc = await FirebaseFirestore.instance.collection('users').doc(otherUser).get();
          if (userDoc.exists && userDoc.data() != null) {
            final userData = userDoc.data()!;
            if (userData['nickname'] != null && userData['nickname'].toString().isNotEmpty) {
              displayName = userData['nickname'].toString();
            } else {
              displayName = 'User ${otherUser.substring(otherUser.length - 4)}';
            }
          } else {
            displayName = 'User ${otherUser.substring(otherUser.length - 4)}';
          }
        } catch (e) {
          displayName = 'User ${otherUser.substring(otherUser.length - 4)}';
        }
      }
      
      data['displayName'] = displayName;
      enrichedDocs.add(data);
    }
    
    return enrichedDocs;
  }

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    _currentUserMobile = appState.mobileNumber;
    if (_currentUserMobile.isEmpty) _currentUserMobile = "test_mobile";

    // Dynamic ID logic: Females use nickname.toLowerCase(), Males use mobileNumber
    String myUid = appState.selectedGender == 'Female' 
        ? appState.uid 
        : _currentUserMobile;
        
    if (myUid.isEmpty) myUid = _currentUserMobile;

    return Scaffold(
      backgroundColor: AppColors.bgLight,
      body: SafeArea(
        child: Column(
          children: [
            // Custom Tab Bar
            Container(
              decoration: const BoxDecoration(
                color: Colors.white,
                border: Border(
                  bottom: BorderSide(color: Color(0xFFE0E0E0), width: 1),
                ),
              ),
              child: Row(
                children: [
                  Expanded(child: _buildTab('FRIENDS', 0)),
                  Expanded(child: _buildTab('GENERAL', 1)),
                ],
              ),
            ),

            // List View connected to Local SQLite
            Expanded(
              child: StreamBuilder<void>(
                // Listen to local DB updates so inbox refreshes automatically
                stream: LocalChatDatabase.instance.updates,
                builder: (context, snapshot) {
                  return FutureBuilder<List<Map<String, dynamic>>>(
                    future: _fetchEnrichedChats(myUid),
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

                          return _buildChatCard(
                            name: displayName,
                            lastMessage: lastMessage,
                            dayText: dayText,
                            unreadCount: unreadCount,
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => HybridChatScreen(
                                    myUid: myUid,
                                    otherUid: otherUser,
                                    otherUserName: displayName,
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

  Widget _buildTab(String title, int index) {
    final isActive = _selectedTab == index;
    return GestureDetector(
      onTap: () {
        setState(() {
          _selectedTab = index;
        });
      },
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: isActive ? AppColors.primaryBlue : Colors.transparent,
              width: 3,
            ),
          ),
        ),
        alignment: Alignment.center,
        child: Text(
          title,
          style: TextStyle(
            color: isActive ? AppColors.primaryBlue : AppColors.textGrey,
            fontWeight: isActive ? FontWeight.bold : FontWeight.w600,
            fontSize: 16,
            letterSpacing: 1,
          ),
        ),
      ),
    );
  }

  Widget _buildChatCard({
    required String name,
    required String lastMessage,
    required String dayText,
    required int unreadCount,
    required VoidCallback onTap,
  }) {
    final colors = [
      const Color(0xFFE91E63), // Pink
      const Color(0xFF9C27B0), // Purple
      const Color(0xFF3F51B5), // Indigo
      const Color(0xFF009688), // Teal
      const Color(0xFFFF9800), // Orange
      const Color(0xFF795548), // Brown
      const Color(0xFF607D8B), // Blue Grey
    ];
    final color = colors[name.hashCode.abs() % colors.length];
    
    String initials = name.length >= 2 ? name.substring(0, 2).toUpperCase() : name.toUpperCase();
    if (name.startsWith('User ') && name.length > 5) {
      initials = 'U${name.substring(name.length - 1)}';
    }

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
            CircleAvatar(
              radius: 28,
              backgroundColor: color,
              child: Text(
                initials,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
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
}
