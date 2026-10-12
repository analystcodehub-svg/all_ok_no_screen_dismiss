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
  DatabaseReference get blockedUsersRef => db.ref('blocked_users');
  DatabaseReference get callLogsRef => db.ref('call_logs');
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
      await ref.runTransaction((currentValue) {
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
    } catch (e) {
      debugPrint('Error incrementing expert stats for $expertId: $e');
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // CALL LOGS
  // ─────────────────────────────────────────────────────────────────────────

  Future<void> saveCallLog(String logId, Map<String, dynamic> logData) async {
    if (logId.isEmpty) return;
    try {
      final clean = _sanitizeForRtdb(logData);
      await callLogsRef.child(logId).update(clean);
    } catch (e) {
      debugPrint('Error saving call log $logId in new RTDB: $e');
    }
  }

  Future<Map<String, dynamic>?> getCallLog(String logId) async {
    if (logId.isEmpty) return null;
    try {
      final snap = await callLogsRef.child(logId).get();
      if (snap.exists && snap.value != null) {
        return Map<String, dynamic>.from(snap.value as Map);
      }
      // Fallback: check Firestore
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
