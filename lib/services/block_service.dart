import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/foundation.dart';
import 'user_database_service.dart';

class BlockService {
  static final BlockService instance = BlockService._internal();
  BlockService._internal();

  final Set<String> _blockedUids = {};
  Set<String> get blockedUids => Set.unmodifiable(_blockedUids);
  String? _currentMyUid;

  /// Fetch blocked users from new RTDB and cache them locally (Single Sync).
  /// Call this when the app starts or user logs in.
  Future<void> syncBlockedUsers(String myUid) async {
    _currentMyUid = myUid;
    try {
      final prefs = await SharedPreferences.getInstance();
      
      // 1. Fetch from new RTDB (with Firestore fallback inside UserDatabaseService)
      final uids = await UserDatabaseService.instance.getBlockedUsers(myUid);
      
      if (uids.isNotEmpty) {
        // 2. Update memory and local cache
        _blockedUids.clear();
        _blockedUids.addAll(uids);
        await prefs.setStringList('blocked_uids_$myUid', uids);
      } else {
        final cached = prefs.getStringList('blocked_uids_$myUid') ?? [];
        _blockedUids.clear();
        _blockedUids.addAll(cached);
      }
    } catch (e) {
      debugPrint('Error syncing blocked users: $e');
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

  /// Asynchronously checks if a user is blocked (Memory -> Local Cache -> Database)
  Future<bool> isUserBlockedAsync(String myUid, String otherUid) async {
    // 1. Check Memory
    if (_blockedUids.contains(otherUid)) return true;

    // 2. Check Local Cache (SharedPreferences)
    final prefs = await SharedPreferences.getInstance();
    final cached = prefs.getStringList('blocked_uids_$myUid') ?? [];
    if (cached.contains(otherUid)) {
      _blockedUids.add(otherUid);
      return true;
    }

    // 3. Check Database
    try {
      final uids = await UserDatabaseService.instance.getBlockedUsers(myUid);
      if (uids.isNotEmpty) {
        await prefs.setStringList('blocked_uids_$myUid', uids);
        _blockedUids.clear();
        _blockedUids.addAll(uids);
        return uids.contains(otherUid);
      }
    } catch (e) {
      debugPrint('Error checking database for block status: $e');
    }

    return false;
  }

  /// Checks if the otherUid is blocked by ANY locally logged-in user.
  /// Useful in background isolates where myUid might not be immediately available.
  Future<bool> isUserBlockedAnywhereAsync(String otherUid) async {
    // 1. Check Memory (if main isolate)
    if (_blockedUids.contains(otherUid)) return true;

    // 2. Check all SharedPreferences keys
    final prefs = await SharedPreferences.getInstance();
    for (String key in prefs.getKeys()) {
      if (key.startsWith('blocked_uids_')) {
        final cached = prefs.getStringList(key) ?? [];
        if (cached.contains(otherUid)) {
          return true;
        }
      }
    }
    return false;
  }

  /// Block a user and update both new RTDB and Local Cache.
  Future<void> blockUser(String myUid, String otherUid) async {
    if (_blockedUids.contains(otherUid)) return;

    _blockedUids.add(otherUid);
    _currentMyUid ??= myUid;

    try {
      // 1. Save to SharedPreferences
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList('blocked_uids_$myUid', _blockedUids.toList());

      // 2. Sync to new RTDB
      await UserDatabaseService.instance.blockUser(myUid, otherUid);
    } catch (e) {
      debugPrint('Error blocking user: $e');
    }
  }

  /// Unblock a user and update both new RTDB and Local Cache.
  Future<void> unblockUser(String myUid, String otherUid) async {
    if (!_blockedUids.contains(otherUid)) return;

    _blockedUids.remove(otherUid);
    _currentMyUid ??= myUid;

    try {
      // 1. Save to SharedPreferences
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList('blocked_uids_$myUid', _blockedUids.toList());

      // 2. Sync to new RTDB
      await UserDatabaseService.instance.unblockUser(myUid, otherUid);
    } catch (e) {
      debugPrint('Error unblocking user: $e');
    }
  }
}
