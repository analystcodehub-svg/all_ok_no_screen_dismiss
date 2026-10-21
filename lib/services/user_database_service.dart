import 'dart:async';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:cloud_firestore/cloud_firestore.dart' hide Transaction;
import 'package:flutter/foundation.dart';

/// Central database service for Male & Female user profiles, expert profiles,
/// blocked users, call logs, reports, and tier applications using the NEW RTDB instance:
/// https://zegochat-c44b0-4cbfb.asia-southeast1.firebasedatabase.app
///
/// NOTE: The existing RTDB instance (zegochat-c44b0) continues exclusively handling
/// calls (WebRTC), status (presence), queues, and chat transit/acks.
/// Firestore strictly continues handling: recharge_history, withdrawal_requests,
/// kyc_requests, audio verification url, and female referrals.
class UserDatabaseService {
  static final UserDatabaseService instance = UserDatabaseService._internal();
  UserDatabaseService._internal();

  static const String databaseUrl =
      'https://zegochat-c44b0-4cbfb.asia-southeast1.firebasedatabase.app';

  late final FirebaseDatabase db = FirebaseDatabase.instanceFor(
    app: Firebase.app(),
    databaseURL: databaseUrl,
  );

  DatabaseReference get usersRef => db.ref('users');
  DatabaseReference get expertsRef => db.ref('experts');

  /// Language buckets of ONLINE experts (new RTDB only): `expert_buckets/{language}/{uid}`
  /// Feeds the male dashboard, ranked by totalTalkSeconds.
  DatabaseReference get expertBucketsRef => db.ref('expert_buckets');
  DatabaseReference get blockedUsersRef => db.ref('blocked_users');
  DatabaseReference get callLogsRef => db.ref('call_logs');
  DatabaseReference get userCallLogsRef => db.ref('user_call_logs');
  DatabaseReference get userChatTransactionsRef => db.ref('user_chat_transactions');
  DatabaseReference get reportsRef => db.ref('reports');
  DatabaseReference get tierApplicationsRef => db.ref('tier_applications');

  // ─────────────────────────────────────────────────────────────────────────
  // USERS (MALE CALLERS)
  // ─────────────────────────────────────────────────────────────────────────

  /// Fetches a male user profile. If not yet in new RTDB, falls back to
  /// Firestore and lazily copies it to RTDB so existing users are never lost.
  Future<Map<String, dynamic>?> getUser(String uid) async {
    if (uid.isEmpty) return null;
    try {
      final snap = await usersRef.child(uid).get();
      if (snap.exists && snap.value != null) {
        return Map<String, dynamic>.from(snap.value as Map);
      }

      // Fallback: Check Firestore users
      try {
        final doc = await FirebaseFirestore.instance.collection('users').doc(uid).get();
        if (doc.exists && doc.data() != null) {
          final data = Map<String, dynamic>.from(doc.data()!);
          // Convert Timestamp to int ms
          final clean = _sanitizeForRtdb(data);
          await usersRef.child(uid).set(clean);
          return clean;
        }
      } catch (e) {
        debugPrint('Firestore fallback getUser error for $uid: $e');
      }
    } catch (e) {
      debugPrint('Error getting user $uid from new RTDB: $e');
    }
    return null;
  }

  /// Sets or updates a male user profile in the new RTDB.
  Future<void> setUser(String uid, Map<String, dynamic> data) async {
    if (uid.isEmpty) return;
    try {
      final sanitized = _sanitizeForRtdb(data);
      await usersRef.child(uid).update(sanitized);
    } catch (e) {
      debugPrint('Error setting user $uid in new RTDB: $e');
      rethrow;
    }
  }

  /// Updates fields on a male user profile.
  Future<void> updateUser(String uid, Map<String, dynamic> data) async {
    if (uid.isEmpty) return;
    try {
      final sanitized = _sanitizeForRtdb(data);
      await usersRef.child(uid).update(sanitized);
    } catch (e) {
      debugPrint('Error updating user $uid in new RTDB: $e');
      rethrow;
    }
  }

  /// Safe RTDB transaction to deduct coin balance for a user.
  Future<bool> deductUserCoins(String uid, int coins) async {
    if (uid.isEmpty || coins <= 0) return false;
    try {
      final coinRef = usersRef.child(uid).child('coinBalance');
      final txResult = await coinRef.runTransaction((currentValue) {
        if (currentValue == null) {
          return Transaction.abort();
        }
        final currentCoins = (currentValue as num).toInt();
        if (currentCoins < coins) {
          return Transaction.abort();
        }
        return Transaction.success(currentCoins - coins);
      });
      return txResult.committed;
    } catch (e) {
      debugPrint('Error deducting coins for user $uid in new RTDB: $e');
      return false;
    }
  }

  /// Safe RTDB transaction to credit/add coin balance for a user upon recharge.
  Future<bool> addUserCoins(String uid, int coins) async {
    if (uid.isEmpty || coins <= 0) return false;
    try {
      final coinRef = usersRef.child(uid).child('coinBalance');
      final txResult = await coinRef.runTransaction((currentValue) {
        final currentCoins = (currentValue as num?)?.toInt() ?? 0;
        return Transaction.success(currentCoins + coins);
      });
      return txResult.committed;
    } catch (e) {
      debugPrint('Error adding coins for user $uid in new RTDB: $e');
      return false;
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // EXPERTS (FEMALE EXPERTS)
  // ─────────────────────────────────────────────────────────────────────────

  /// Fetches a female expert profile. If not yet in new RTDB, falls back to
  /// Firestore and lazily copies it to RTDB.
  Future<Map<String, dynamic>?> getExpert(String uid) async {
    if (uid.isEmpty) return null;
    try {
      final snap = await expertsRef.child(uid).get();
      if (snap.exists && snap.value != null) {
        return Map<String, dynamic>.from(snap.value as Map);
      }

      // Fallback: Check Firestore experts
      try {
        final doc = await FirebaseFirestore.instance.collection('experts').doc(uid).get();
        if (doc.exists && doc.data() != null) {
          final data = Map<String, dynamic>.from(doc.data()!);
          final clean = _sanitizeForRtdb(data);
          await expertsRef.child(uid).set(clean);
          return clean;
        }
      } catch (e) {
        debugPrint('Firestore fallback getExpert error for $uid: $e');
      }
    } catch (e) {
      debugPrint('Error getting expert $uid from new RTDB: $e');
    }
    return null;
  }

  /// Sets or updates a female expert profile in new RTDB.
  Future<void> setExpert(String uid, Map<String, dynamic> data) async {
    if (uid.isEmpty) return;
    try {
      final sanitized = _sanitizeForRtdb(data);
      await expertsRef.child(uid).update(sanitized);
    } catch (e) {
      debugPrint('Error setting expert $uid in new RTDB: $e');
      rethrow;
    }
  }

  /// Updates fields on a female expert profile in new RTDB.
  Future<void> updateExpert(String uid, Map<String, dynamic> data) async {
    if (uid.isEmpty) return;
    try {
      final sanitized = _sanitizeForRtdb(data);
      await expertsRef.child(uid).update(sanitized);
    } catch (e) {
      debugPrint('Error updating expert $uid in new RTDB: $e');
      rethrow;
    }
  }

  /// Stream expert profile stats (earnings, talk time, avatar, rating).
  Stream<DatabaseEvent> streamExpert(String uid) {
    return expertsRef.child(uid).onValue;
  }

  /// Atomically increment expert earnings, redeemable balance, and talk time.
  Future<void> incrementExpertStats(
    String expertId, {
    required double earned,
    required int seconds,
    required int minutesToAdd,
  }) async {
    if (expertId.isEmpty) return;
    try {
      final ref = expertsRef.child(expertId);
      final result = await ref.runTransaction((currentValue) {
        Map<String, dynamic> data = {};
        if (currentValue != null && currentValue is Map) {
          data = Map<String, dynamic>.from(currentValue);
        }
        final double curEarnings = (data['totalEarnings'] as num?)?.toDouble() ?? 0.0;
        final double curRedeemable = (data['redeemableBalance'] as num?)?.toDouble() ?? 0.0;
        final int curSeconds = (data['totalTalkSeconds'] as num?)?.toInt() ?? 0;
        final int curMinutes = (data['totalTalktimeMinutes'] as num?)?.toInt() ?? 0;

        data['totalEarnings'] = curEarnings + earned;
        data['redeemableBalance'] = curRedeemable + earned;
        data['totalTalkSeconds'] = curSeconds + seconds;
        data['totalTalktimeMinutes'] = curMinutes + minutesToAdd;
        data['lastCallAt'] = ServerValue.timestamp;

        return Transaction.success(data);
      });

      // Keep the language-bucket ranking in sync with the profile.
      await _syncBucketTalkSeconds(expertId, result.snapshot.value);
    } catch (e) {
      debugPrint('Error incrementing expert stats for $expertId: $e');
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // EXPERT LANGUAGE BUCKETS (online experts, feeds the male dashboard)
  // Lives ONLY in this new RTDB: expert_buckets/<language>/<uid>
  // ─────────────────────────────────────────────────────────────────────────

  StreamSubscription<DatabaseEvent>? _bucketConnectionSub;

  /// Bucket key for a language name, e.g. "Hindi" -> "hindi". Must be used by
  /// both the expert (writer) and the male dashboard (reader).
  static String bucketKeyFor(String? language) {
    final key = (language ?? '').trim().toLowerCase();
    return key.isEmpty ? 'hindi' : key;
  }

  /// Puts the expert into her language bucket and keeps her there while the
  /// connection is alive. Re-publishes automatically after a network drop
  /// (the server-side onDisconnect removes the entry when the socket dies).
  Future<void> joinExpertBucket(String expertId, String language) async {
    if (expertId.isEmpty) return;
    await _bucketConnectionSub?.cancel();
    _bucketConnectionSub = db.ref('.info/connected').onValue.listen((event) {
      if (event.snapshot.value == true) {
        publishExpertBucketEntry(expertId, language);
      }
    });
  }

  /// Removes the expert from her language bucket (went offline / logged out).
  Future<void> leaveExpertBucket(String expertId, String language) async {
    await _bucketConnectionSub?.cancel();
    _bucketConnectionSub = null;
    if (expertId.isEmpty) return;
    try {
      final ref = expertBucketsRef.child(bucketKeyFor(language)).child(expertId);
      await ref.remove();
      await ref.onDisconnect().cancel();
    } catch (e) {
      debugPrint('Error leaving expert bucket for $expertId: $e');
    }
  }

  /// Writes (or refreshes) the bucket entry and arms onDisconnect().remove().
  /// Safe to call repeatedly; never throws.
  Future<void> publishExpertBucketEntry(String expertId, String language) async {
    if (expertId.isEmpty) return;
    try {
      final profile = await getExpert(expertId);
      final ref = expertBucketsRef.child(bucketKeyFor(language)).child(expertId);
      final dynamic avatarUrl = profile?['profileImageUrl'] ?? profile?['avatarUrl'];

      await ref.set({
        'totalTalkSeconds': (profile?['totalTalkSeconds'] as num?)?.toInt() ?? 0,
        'nickname': profile?['nickname'] ?? 'Expert',
        'age': (profile?['age'] as num?)?.toInt() ?? 22,
        'avatarIndex': (profile?['avatarIndex'] as num?)?.toInt() ?? 1,
        if (avatarUrl is String && avatarUrl.isNotEmpty) 'avatarUrl': avatarUrl,
        'timestamp': ServerValue.timestamp,
      });
      await ref.onDisconnect().remove();
    } catch (e) {
      debugPrint('Error publishing expert bucket entry for $expertId: $e');
    }
  }

  /// Updates totalTalkSeconds on the bucket entry ONLY if it already exists.
  Future<void> _syncBucketTalkSeconds(String expertId, Object? profile) async {
    try {
      if (profile is! Map) return;
      final int totalSeconds = (profile['totalTalkSeconds'] as num?)?.toInt() ?? 0;
      final String bucket = bucketKeyFor(profile['languages']?.toString());
      await expertBucketsRef.child(bucket).child(expertId).runTransaction((cur) {
        if (cur == null || cur is! Map) return Transaction.abort(); // not online, don't create
        final data = Map<String, dynamic>.from(cur);
        data['totalTalkSeconds'] = totalSeconds;
        return Transaction.success(data);
      });
    } catch (e) {
      debugPrint('Error syncing bucket talk seconds for $expertId: $e');
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // CALL LOGS (Capped to last 10 calls per user in user_call_logs/{uid})
  // ─────────────────────────────────────────────────────────────────────────

  Future<void> saveCallLog(
    String logId,
    Map<String, dynamic> logData, {
    bool isFinal = false,
  }) async {
    if (logId.isEmpty) return;
    try {
      final clean = _sanitizeForRtdb(logData);
      final callerId = clean['callerId']?.toString() ?? '';
      final receiverId = clean['receiverId']?.toString() ?? '';

      // 1. Root call_logs node holds active handshake during call
      await callLogsRef.child(logId).update(clean);

      // 2. Caller's personal recent calls node (incremental & final)
      if (callerId.isNotEmpty) {
        await userCallLogsRef.child(callerId).child(logId).update(clean);
      }

      // 3. When call finishes (isFinal = true):
      if (isFinal) {
        // Also add to receiver's personal recent calls
        if (receiverId.isNotEmpty) {
          await userCallLogsRef.child(receiverId).child(logId).update(clean);
        }

        // Cap to last 10 calls per user (deletes oldest excess calls) as requested
        if (callerId.isNotEmpty) {
          _pruneOldCallLogs(callerId, maxKeep: 10);
        }
        if (receiverId.isNotEmpty) {
          _pruneOldCallLogs(receiverId, maxKeep: 10);
        }

        // Clean up temporary root call_log handshake after 60s
        // so root 'call_logs' never bloats the database!
        Future.delayed(const Duration(seconds: 60), () {
          callLogsRef.child(logId).remove().catchError((_) {});
        });
      }
    } catch (e) {
      debugPrint('Error saving call log $logId in new RTDB: $e');
    }
  }

  Future<Map<String, dynamic>?> getCallLog(String logId, {String? callerId}) async {
    if (logId.isEmpty) return null;
    try {
      // 1. Check temporary root call_logs
      final snap = await callLogsRef.child(logId).get();
      if (snap.exists && snap.value != null) {
        return Map<String, dynamic>.from(snap.value as Map);
      }

      // 2. Check caller's user_call_logs if callerId is provided
      if (callerId != null && callerId.isNotEmpty) {
        final userSnap = await userCallLogsRef.child(callerId).child(logId).get();
        if (userSnap.exists && userSnap.value != null) {
          return Map<String, dynamic>.from(userSnap.value as Map);
        }
      }

      // 3. Fallback: check Firestore
      final doc = await FirebaseFirestore.instance.collection('call_logs').doc(logId).get();
      if (doc.exists && doc.data() != null) {
        final data = Map<String, dynamic>.from(doc.data()!);
        return _sanitizeForRtdb(data);
      }
    } catch (e) {
      debugPrint('Error getting call log $logId: $e');
    }
    return null;
  }

  /// Fetches up to [limit] recent call logs for a user from new RTDB. Default 10.
  Future<List<Map<String, dynamic>>> getUserCallLogs(String userId, {int limit = 10}) async {
    if (userId.isEmpty) return [];
    try {
      final snap = await userCallLogsRef
          .child(userId)
          .orderByChild('timestamp')
          .limitToLast(limit)
          .get();
      if (snap.exists && snap.value != null) {
        final data = Map<dynamic, dynamic>.from(snap.value as Map);
        final list = <Map<String, dynamic>>[];
        for (final entry in data.entries) {
          if (entry.value is Map) {
            list.add(Map<String, dynamic>.from(entry.value as Map));
          }
        }
        list.sort((a, b) {
          final aTime = (a['timestamp'] as num?)?.toInt() ?? 0;
          final bTime = (b['timestamp'] as num?)?.toInt() ?? 0;
          return bTime.compareTo(aTime); // descending (newest first)
        });
        return list;
      }
    } catch (e) {
      debugPrint('Error getting user call logs for $userId: $e');
    }
    return [];
  }

  /// Automatically keeps only the newest [maxKeep] (10) calls for a user,
  /// deleting the oldest ones in RTDB.
  Future<void> _pruneOldCallLogs(String userId, {int maxKeep = 10}) async {
    if (userId.isEmpty) return;
    try {
      final snap = await userCallLogsRef.child(userId).get();
      if (!snap.exists || snap.value == null) return;
      final data = Map<dynamic, dynamic>.from(snap.value as Map);
      if (data.length <= maxKeep) return;

      final entries = data.entries.toList();
      // Sort oldest first
      entries.sort((a, b) {
        final aTime = (a.value is Map ? (a.value['timestamp'] as num?)?.toInt() : null) ?? 0;
        final bTime = (b.value is Map ? (b.value['timestamp'] as num?)?.toInt() : null) ?? 0;
        return aTime.compareTo(bTime);
      });

      final removeCount = entries.length - maxKeep;
      final updates = <String, Object?>{};
      for (int i = 0; i < removeCount; i++) {
        updates[entries[i].key.toString()] = null; // null deletes key in RTDB
      }
      await userCallLogsRef.child(userId).update(updates);
    } catch (e) {
      debugPrint('Error pruning call logs for $userId: $e');
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // CHAT TRANSACTIONS (Capped to last 5 transactions per male user in RTDB)
  // ─────────────────────────────────────────────────────────────────────────

  Future<void> saveChatTransaction(String userId, Map<String, dynamic> txData) async {
    if (userId.isEmpty) return;
    try {
      final clean = _sanitizeForRtdb(txData);
      final txId = clean['txId']?.toString() ?? DateTime.now().millisecondsSinceEpoch.toString();
      await userChatTransactionsRef.child(userId).child(txId).update(clean);

      // Auto-prune to keep max 5 chat transactions per user in RTDB
      _pruneOldChatTransactions(userId, maxKeep: 5);
    } catch (e) {
      debugPrint('Error saving chat transaction in RTDB: $e');
    }
  }

  Future<List<Map<String, dynamic>>> getUserChatTransactions(String userId, {int limit = 5}) async {
    if (userId.isEmpty) return [];
    try {
      final snap = await userChatTransactionsRef
          .child(userId)
          .orderByChild('timestamp')
          .limitToLast(limit)
          .get();
      if (snap.exists && snap.value != null) {
        final data = Map<dynamic, dynamic>.from(snap.value as Map);
        final list = <Map<String, dynamic>>[];
        for (final entry in data.entries) {
          if (entry.value is Map) {
            list.add(Map<String, dynamic>.from(entry.value as Map));
          }
        }
        list.sort((a, b) {
          final aTime = (a['timestamp'] as num?)?.toInt() ?? 0;
          final bTime = (b['timestamp'] as num?)?.toInt() ?? 0;
          return bTime.compareTo(aTime); // descending (newest first)
        });
        return list;
      }
    } catch (e) {
      debugPrint('Error getting chat transactions for $userId: $e');
    }
    return [];
  }

  Future<void> _pruneOldChatTransactions(String userId, {int maxKeep = 5}) async {
    if (userId.isEmpty) return;
    try {
      final snap = await userChatTransactionsRef.child(userId).get();
      if (!snap.exists || snap.value == null) return;
      final data = Map<dynamic, dynamic>.from(snap.value as Map);
      if (data.length <= maxKeep) return;

      final entries = data.entries.toList();
      // Sort oldest first
      entries.sort((a, b) {
        final aTime = (a.value is Map ? (a.value['timestamp'] as num?)?.toInt() : null) ?? 0;
        final bTime = (b.value is Map ? (b.value['timestamp'] as num?)?.toInt() : null) ?? 0;
        return aTime.compareTo(bTime);
      });

      final removeCount = entries.length - maxKeep;
      final updates = <String, Object?>{};
      for (int i = 0; i < removeCount; i++) {
        updates[entries[i].key.toString()] = null; // null deletes key in RTDB
      }
      await userChatTransactionsRef.child(userId).update(updates);
    } catch (e) {
      debugPrint('Error pruning chat transactions for $userId: $e');
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // REPORTS
  // ─────────────────────────────────────────────────────────────────────────

  Future<void> submitReport(Map<String, dynamic> reportData) async {
    try {
      final clean = _sanitizeForRtdb(reportData);
      clean['timestamp'] = ServerValue.timestamp;
      await reportsRef.push().set(clean);
    } catch (e) {
      debugPrint('Error submitting report in new RTDB: $e');
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // TIER APPLICATIONS
  // ─────────────────────────────────────────────────────────────────────────

  Future<void> submitTierApplication(Map<String, dynamic> appData) async {
    try {
      final clean = _sanitizeForRtdb(appData);
      clean['timestamp'] = ServerValue.timestamp;
      await tierApplicationsRef.push().set(clean);
    } catch (e) {
      debugPrint('Error submitting tier application in new RTDB: $e');
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // BLOCKED USERS
  // ─────────────────────────────────────────────────────────────────────────

  Future<List<String>> getBlockedUsers(String myUid) async {
    if (myUid.isEmpty) return [];
    try {
      final snap = await blockedUsersRef.child(myUid).get();
      if (snap.exists && snap.value != null) {
        if (snap.value is Map) {
          final map = snap.value as Map;
          return map.keys.map((k) => k.toString()).toList();
        } else if (snap.value is List) {
          final list = snap.value as List;
          return list.where((e) => e != null).map((e) => e.toString()).toList();
        }
      }

      // Fallback: check Firestore blocked_users
      final doc = await FirebaseFirestore.instance.collection('blocked_users').doc(myUid).get();
      if (doc.exists && doc.data() != null) {
        final uids = List<String>.from(doc.data()?['blocked_uids'] ?? doc.data()?['uids'] ?? []);
        // Save to RTDB
        for (String uid in uids) {
          await blockedUsersRef.child(myUid).child(uid).set(true);
        }
        return uids;
      }
    } catch (e) {
      debugPrint('Error getting blocked users for $myUid: $e');
    }
    return [];
  }

  Future<void> blockUser(String myUid, String otherUid) async {
    if (myUid.isEmpty || otherUid.isEmpty) return;
    try {
      await blockedUsersRef.child(myUid).child(otherUid).set(true);
    } catch (e) {
      debugPrint('Error blocking user in new RTDB: $e');
    }
  }

  Future<void> unblockUser(String myUid, String otherUid) async {
    if (myUid.isEmpty || otherUid.isEmpty) return;
    try {
      await blockedUsersRef.child(myUid).child(otherUid).remove();
    } catch (e) {
      debugPrint('Error unblocking user in new RTDB: $e');
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // HELPERS
  // ─────────────────────────────────────────────────────────────────────────

  Map<String, dynamic> _sanitizeForRtdb(Map<String, dynamic> data) {
    final Map<String, dynamic> clean = {};
    data.forEach((key, value) {
      if (value is Timestamp) {
        clean[key] = value.millisecondsSinceEpoch;
      } else if (value is FieldValue) {
        clean[key] = ServerValue.timestamp;
      } else if (value is Map) {
        clean[key] = _sanitizeForRtdb(Map<String, dynamic>.from(value));
      } else {
        clean[key] = value;
      }
    });
    return clean;
  }
}
