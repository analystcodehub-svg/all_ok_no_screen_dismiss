import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:provider/provider.dart';
import '../services/block_service.dart';
import '../providers/app_state.dart';
import '../theme/app_theme.dart';

class BlockedUsersScreen extends StatefulWidget {
  const BlockedUsersScreen({Key? key}) : super(key: key);

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
      final doc = await FirebaseFirestore.instance.collection('blocked_users').doc(myUid).get();
      
      _blockedUsers.clear();
      
      if (doc.exists) {
        final uids = List<String>.from(doc.data()?['blocked_uids'] ?? doc.data()?['uids'] ?? []);
        
        for (String uid in uids) {
          // Try to fetch nickname if available from users/experts
          String name = 'Unknown User';
          try {
            final userDoc = await FirebaseFirestore.instance.collection('users').doc(uid).get();
            if (userDoc.exists) {
              name = userDoc.data()?['nickname'] ?? 'Unknown User';
            } else {
              final expertDoc = await FirebaseFirestore.instance.collection('experts').doc(uid).get();
              if (expertDoc.exists) {
                name = expertDoc.data()?['nickname'] ?? 'Unknown Expert';
              }
            }
          } catch (_) {}
          
          _blockedUsers.add({'uid': uid, 'name': name});
        }
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
                          backgroundColor: Colors.red.withOpacity(0.1),
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
    );
  }
}
