import 'dart:async';
import 'dart:math';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/foundation.dart';
import 'user_database_service.dart';

/// Dedicated service managing the 1-minute free intro calling system from female to new male users.
/// Operates strictly on the new isolated Realtime Database instance:
/// https://zegochat-c44b0-1e689.asia-southeast1.firebasedatabase.app
///
/// Ensures zero modifications or conflicts with existing user profiles or call queues.
class NewMaleService {
  static final NewMaleService instance = NewMaleService._internal();
  NewMaleService._internal();

  static const String newDbUrl =
      'https://zegochat-c44b0-1e689.asia-southeast1.firebasedatabase.app';

  late final FirebaseDatabase db = FirebaseDatabase.instanceFor(
    app: Firebase.app(),
    databaseURL: newDbUrl,
  );

  DatabaseReference get newMalesPoolRef => db.ref('new_males_pool');
  DatabaseReference get freeIntroCallsRef => db.ref('free_intro_call_records');
  DatabaseReference get callsRef => db.ref('calls');

  /// Check whether a male user is eligible for the single-time 1-minute intro call.
  Future<bool> isEligible(String maleUid) async {
    if (maleUid.isEmpty) return false;
    try {
      final snap = await freeIntroCallsRef.child(maleUid).get();
      if (snap.exists && snap.value != null) {
        final data = Map<String, dynamic>.from(snap.value as Map);
        if (data['used'] == true) {
          return false;
        }
      }
      return true;
    } catch (e) {
      debugPrint('[NewMaleService] Error checking eligibility for $maleUid: $e');
      return true;
    }
  }

  /// Mark the 1-minute free intro call as used so the male user cannot receive another free call.
  Future<void> markFreeCallUsed({
    required String maleUid,
    required String femaleUid,
    required int durationSeconds,
  }) async {
    if (maleUid.isEmpty) return;
    try {
      await freeIntroCallsRef.child(maleUid).set({
        'used': true,
        'usedAt': ServerValue.timestamp,
        'femaleId': femaleUid,
        'durationSeconds': durationSeconds,
      });

      // Remove from discovery pool so they no longer display in the female carousel
      await newMalesPoolRef.child(maleUid).remove();
      debugPrint('[NewMaleService] Marked free call used for $maleUid by female $femaleUid');
    } catch (e) {
      debugPrint('[NewMaleService] Error marking free call used: $e');
    }
  }

  /// Register or update male user in the new_males_pool on the new RTDB instance.
  Future<void> registerOrUpdateMale({
    required String uid,
    required String nickname,
    String? avatarUrl,
    int avatarIndex = 1,
    String? fcmToken,
    bool isOnline = true,
  }) async {
    if (uid.isEmpty) return;
    try {
      final eligible = await isEligible(uid);
      if (!eligible) {
        debugPrint('[NewMaleService] User $uid already consumed free intro call, skipping registration.');
        return;
      }

      final Map<String, dynamic> data = {
        'uid': uid,
        'nickname': nickname.isNotEmpty ? nickname : 'User',
        'avatarUrl': avatarUrl ?? '',
        'avatarIndex': avatarIndex,
        'fcmToken': fcmToken ?? '',
        'isOnline': isOnline,
        'lastSeen': ServerValue.timestamp,
      };

      await newMalesPoolRef.child(uid).update(data);
      debugPrint('[NewMaleService] Successfully synced male $uid to new_males_pool');
    } catch (e) {
      debugPrint('[NewMaleService] Error registering male $uid: $e');
    }
  }

  /// Real-time stream of up to [limit] new male users from the new RTDB instance.
  Stream<List<Map<String, dynamic>>> streamNewMales({int limit = 20}) {
    return newMalesPoolRef.limitToLast(limit).onValue.map((event) {
      final List<Map<String, dynamic>> list = [];
      if (event.snapshot.exists && event.snapshot.value != null) {
        final map = Map<String, dynamic>.from(event.snapshot.value as Map);
        map.forEach((k, v) {
          if (v is Map) {
            final item = Map<String, dynamic>.from(v);
            item['uid'] = k;
            list.add(item);
          }
        });
      }
      return list.reversed.toList();
    });
  }

  /// Fetch up to [limit] new males with automatic fallback seeding from existing users
  /// so that 20 users are always available for the female screen.
  Future<List<Map<String, dynamic>>> fetchNewMalesWithFallback({int limit = 20}) async {
    final List<Map<String, dynamic>> result = [];
    try {
      final snap = await newMalesPoolRef.limitToLast(limit).get();
      if (snap.exists && snap.value != null) {
        final map = Map<String, dynamic>.from(snap.value as Map);
        map.forEach((k, v) {
          if (v is Map) {
            final item = Map<String, dynamic>.from(v);
            item['uid'] = k;
            result.add(item);
          }
        });
      }
    } catch (e) {
      debugPrint('[NewMaleService] Error fetching pool from new RTDB: $e');
    }

    // If pool has fewer than desired limit, seed from existing users in UserDatabaseService
    if (result.length < limit) {
      try {
        final existingSnap = await UserDatabaseService.instance.usersRef
            .limitToLast(limit * 3)
            .get();

        if (existingSnap.exists && existingSnap.value != null) {
          final usersMap = Map<String, dynamic>.from(existingSnap.value as Map);
          for (var entry in usersMap.entries) {
            if (result.length >= limit) break;
            final uid = entry.key;
            if (result.any((u) => u['uid'] == uid)) continue;

            final isElig = await isEligible(uid);
            if (!isElig) continue;

            if (entry.value is Map) {
              final uData = Map<String, dynamic>.from(entry.value as Map);
              final item = <String, dynamic>{
                'uid': uid,
                'nickname': uData['nickname'] ?? uData['name'] ?? 'User',
                'avatarUrl': uData['profileImageUrl'] ?? uData['avatarUrl'] ?? '',
                'avatarIndex': (uData['avatarIndex'] as num?)?.toInt() ?? 1,
                'fcmToken': uData['fcmToken'] ?? '',
                'isOnline': true,
                'lastSeen': DateTime.now().millisecondsSinceEpoch,
              };
              result.add(item);

              // Seed to new RTDB asynchronously
              newMalesPoolRef.child(uid).set(item).catchError((err) {
                debugPrint('[NewMaleService] Failed async seeding for $uid: $err');
              });
            }
          }
        }
      } catch (e) {
        debugPrint('[NewMaleService] Fallback seed error: $e');
      }
    }

    return result;
  }

  /// Pick a random eligible male from the available 20 candidates.
  Future<Map<String, dynamic>?> pickRandomMale(Iterable<String> excludedUids) async {
    final list = await fetchNewMalesWithFallback(limit: 20);
    final excludedSet = excludedUids.toSet();
    final candidates = list.where((m) => !excludedSet.contains(m['uid'])).toList();
    if (candidates.isEmpty) return null;
    final rand = Random();
    return candidates[rand.nextInt(candidates.length)];
  }
}
