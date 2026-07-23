import 'package:shared_preferences/shared_preferences.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

class BlockService {
  static final BlockService instance = BlockService._internal();
  BlockService._internal();

  final Set<String> _blockedUids = {};
  String? _currentMyUid;

  /// Fetch blocked users from Firestore and cache them locally (Single Sync).
  /// Call this when the app starts or user logs in.
  Future<void> syncBlockedUsers(String myUid) async {
    _currentMyUid = myUid;
    try {
      final prefs = await SharedPreferences.getInstance();
      
      // 1. Fetch from Firestore (Single sync)
      final doc = await FirebaseFirestore.instance.collection('blocked_users').doc(myUid).get();
      
      if (doc.exists && doc.data() != null) {
        final data = doc.data()!;
        final uids = List<String>.from(data['uids'] ?? []);
        
        // 2. Update memory and local cache
        _blockedUids.clear();
        _blockedUids.addAll(uids);
        await prefs.setStringList('blocked_uids_$myUid', uids);
      } else {
        // If Firestore has no document, check if we have local cache
        final cached = prefs.getStringList('blocked_uids_$myUid') ?? [];
        _blockedUids.clear();
        _blockedUids.addAll(cached);
      }
    } catch (e) {
      debugPrint('Error syncing blocked users: $e');
      // Fallback to local cache
      final prefs = await SharedPreferences.getInstance();
      final cached = prefs.getStringList('blocked_uids_$myUid') ?? [];
      _blockedUids.clear();
      _blockedUids.addAll(cached);
    }
  }

  /// Check if a user is blocked (Synchronous, ultra-fast memory lookup).
  bool isBlocked(String uid) {
    return _blockedUids.contains(uid);
  }

  /// Block a user and update both Firestore and Local Cache.
  Future<void> blockUser(String myUid, String otherUid) async {
    if (_blockedUids.contains(otherUid)) return;

    _blockedUids.add(otherUid);
    _currentMyUid ??= myUid;

    try {
      // 1. Save to SharedPreferences
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList('blocked_uids_$myUid', _blockedUids.toList());

      // 2. Sync to Firestore
      await FirebaseFirestore.instance.collection('blocked_users').doc(myUid).set({
        'uids': FieldValue.arrayUnion([otherUid]),
        'blocked_uids': FieldValue.arrayUnion([otherUid]) // For cloud function backwards compatibility
      }, SetOptions(merge: true));
    } catch (e) {
      debugPrint('Error blocking user: $e');
    }
  }

  /// Unblock a user and update both Firestore and Local Cache.
  Future<void> unblockUser(String myUid, String otherUid) async {
    if (!_blockedUids.contains(otherUid)) return;

    _blockedUids.remove(otherUid);
    _currentMyUid ??= myUid;

    try {
      // 1. Save to SharedPreferences
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList('blocked_uids_$myUid', _blockedUids.toList());

      // 2. Sync to Firestore
      await FirebaseFirestore.instance.collection('blocked_users').doc(myUid).set({
        'uids': FieldValue.arrayRemove([otherUid]),
        'blocked_uids': FieldValue.arrayRemove([otherUid])
      }, SetOptions(merge: true));
    } catch (e) {
      debugPrint('Error unblocking user: $e');
    }
  }
}
