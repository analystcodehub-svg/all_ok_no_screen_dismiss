import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/block_service.dart';
import '../providers/app_state.dart';
import '../services/user_database_service.dart';
import '../theme/app_theme.dart';

class BlockedUsersScreen extends StatefulWidget {
  const BlockedUsersScreen({super.key});

  @override
  State<BlockedUsersScreen> createState() => _BlockedUsersScreenState();
}

class _BlockedUsersScreenState extends State<BlockedUsersScreen> {
  final List<Map<String, dynamic>> _blockedUsers = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadBlockedUsers();
  }

  Future<void> _loadBlockedUsers() async {
    setState(() => _isLoading = true);
    try {
      final myUid = context.read<AppState>().uid;
      final uids = await UserDatabaseService.instance.getBlockedUsers(myUid);
      
      _blockedUsers.clear();
      
      for (String uid in uids) {
        String name = 'Unknown User';
        try {
          final userData = await UserDatabaseService.instance.getUser(uid);
          if (userData != null) {
            name = userData['nickname'] ?? 'Unknown User';
          } else {
            final expertData = await UserDatabaseService.instance.getExpert(uid);
            if (expertData != null) {
              name = expertData['nickname'] ?? 'Unknown Expert';
            }
          }
        } catch (_) {}
        
        _blockedUsers.add({'uid': uid, 'name': name});
      }
    } catch (e) {
      debugPrint('Error loading blocked users: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _unblockUser(String otherUid) async {
    final myUid = context.read<AppState>().uid;
    await BlockService.instance.unblockUser(myUid, otherUid);
    await _loadBlockedUsers();
    
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('User unblocked successfully.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Blocked Users'),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0,
      ),
      backgroundColor: Colors.grey[50],
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _blockedUsers.isEmpty
              ? const Center(
                  child: Text(
                    'No blocked users.',
                    style: TextStyle(color: AppTheme.textGrey, fontSize: 16),
                  ),
                )
              : ListView.builder(
                  itemCount: _blockedUsers.length,
                  itemBuilder: (context, index) {
                    final user = _blockedUsers[index];
                    return Card(
                      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: Colors.red.withValues(alpha: 0.1),
                          child: const Icon(Icons.person_off, color: Colors.red),
                        ),
                        title: Text(user['name'], style: const TextStyle(fontWeight: FontWeight.bold)),
                        subtitle: const Text('Blocked'),
                        trailing: OutlinedButton(
                          onPressed: () => _unblockUser(user['uid']),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.green,
                            side: const BorderSide(color: Colors.green),
                          ),
                          child: const Text('Unblock'),
                        ),
                      ),
                    );
                  },
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
          currentIndex: 0, // Default to home since they came from there
          onTap: (index) {
            Navigator.pop(context);
          },
          type: BottomNavigationBarType.fixed,
          backgroundColor: Colors.white,
          selectedItemColor: AppTheme.primaryBlue,
          unselectedItemColor: Colors.grey.shade500,
          selectedLabelStyle: const TextStyle(fontWeight: FontWeight.bold),
          unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.normal),
          items: [
            const BottomNavigationBarItem(
              icon: Icon(Icons.home_outlined),
              activeIcon: Icon(Icons.home),
              label: 'Home',
            ),
            BottomNavigationBarItem(
              icon: _buildIconWithBadge(Icons.chat_bubble_outline, '1'),
              activeIcon: _buildIconWithBadge(Icons.chat_bubble, '1', isActive: true),
              label: 'Chat',
            ),
            BottomNavigationBarItem(
              icon: _buildIconWithBadge(Icons.history, '1'),
              activeIcon: _buildIconWithBadge(Icons.history, '1', isActive: true),
              label: 'Recent',
            ),
            const BottomNavigationBarItem(
              icon: Icon(Icons.person_outline),
              activeIcon: Icon(Icons.person),
              label: 'Profile',
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildIconWithBadge(IconData icon, String count, {bool isActive = false}) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Icon(icon, size: 26),
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
}
