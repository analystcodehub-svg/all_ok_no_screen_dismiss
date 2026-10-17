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
/// Features:
/// 1. Language-based bucketing (`new_males_buckets/{languageKey}/{uid}`)
/// 2. Language-based indexing (`new_males_pool/{uid}` indexed on languageKey, isOnline, lastSeen)
/// 3. Language-aware random matchmaking call
/// 4. Single-use 1-minute free call tracking (`free_intro_call_records/{uid}`)
class NewMaleService {
  static final NewMaleService instance = NewMaleService._internal();
  NewMaleService._internal();

  static const String newDbUrl =
      'https://zegochat-c44b0-1e689.asia-southeast1.firebasedatabase.app';

  late final FirebaseDatabase db = FirebaseDatabase.instanceFor(
    app: Firebase.app(),
    databaseURL: newDbUrl,
  );

  /// Master pool of all new males
  DatabaseReference get newMalesPoolRef => db.ref('new_males_pool');

  /// Language-partitioned buckets of new males: `new_males_buckets/{languageKey}/{uid}`
  DatabaseReference get newMalesBucketsRef => db.ref('new_males_buckets');

  /// Single-use free intro call logs
  DatabaseReference get freeIntroCallsRef => db.ref('free_intro_call_records');

  /// Active calls collection on the isolated RTDB
  DatabaseReference get callsRef => db.ref('calls');

  /// Normalizes a language string to a clean, lowercased bucket key (e.g., "Hindi" -> "hindi", "Hindi - Punjabi" -> "hindi")
  static String bucketKeyFor(String? language) {
    if (language == null) return 'hindi';
    final trimmed = language.trim().toLowerCase();
    if (trimmed.isEmpty) return 'hindi';
    final clean = trimmed.split(RegExp(r'[\s\-_/,]+')).first;
    return clean.isEmpty ? 'hindi' : clean;
  }

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
    String? language,
  }) async {
    if (maleUid.isEmpty) return;
    try {
      await freeIntroCallsRef.child(maleUid).set({
        'used': true,
        'usedAt': ServerValue.timestamp,
        'femaleId': femaleUid,
        'durationSeconds': durationSeconds,
      });

      // Remove from discovery pool and language buckets so they no longer appear
      await newMalesPoolRef.child(maleUid).remove();
      if (language != null && language.isNotEmpty) {
        await newMalesBucketsRef.child(bucketKeyFor(language)).child(maleUid).remove();
      }
      await newMalesBucketsRef.child('all').child(maleUid).remove();
      debugPrint('[NewMaleService] Marked free call used for $maleUid by female $femaleUid');
    } catch (e) {
      debugPrint('[NewMaleService] Error marking free call used: $e');
    }
  }

  /// Register or update male user in the new_males_pool and language buckets on the new RTDB instance.
  Future<void> registerOrUpdateMale({
    required String uid,
    required String nickname,
    String? avatarUrl,
    int avatarIndex = 1,
    String language = 'Hindi',
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

      final langKey = bucketKeyFor(language);
      final Map<String, dynamic> data = {
        'uid': uid,
        'nickname': nickname.isNotEmpty ? nickname : 'User',
        'avatarUrl': avatarUrl ?? '',
        'avatarIndex': avatarIndex,
        'language': language.isNotEmpty ? language : 'Hindi',
        'languageKey': langKey,
        'fcmToken': fcmToken ?? '',
        'isOnline': isOnline,
        'lastSeen': ServerValue.timestamp,
      };

      // 1. Write to master pool
      await newMalesPoolRef.child(uid).update(data);

      // 2. Write to language bucket: new_males_buckets/{languageKey}/{uid}
      await newMalesBucketsRef.child(langKey).child(uid).update(data);

      // 3. Write to global 'all' bucket: new_males_buckets/all/{uid}
      await newMalesBucketsRef.child('all').child(uid).update(data);

      debugPrint('[NewMaleService] Successfully synced male $uid to pool & bucket [$langKey]');
    } catch (e) {
      debugPrint('[NewMaleService] Error registering male $uid: $e');
    }
  }

  /// Configure onDisconnect hooks for real-time presence cleanup in buckets
  void setMaleOfflineOnDisconnect(String uid, {String? language}) {
    if (uid.isEmpty) return;
    try {
      final langKey = bucketKeyFor(language);
      final updates = {
        'isOnline': false,
        'lastSeen': ServerValue.timestamp,
      };
      newMalesPoolRef.child(uid).onDisconnect().update(updates);
      newMalesBucketsRef.child(langKey).child(uid).onDisconnect().update(updates);
      newMalesBucketsRef.child('all').child(uid).onDisconnect().update(updates);
    } catch (e) {
      debugPrint('[NewMaleService] Error setting onDisconnect: $e');
    }
  }

  /// Real-time stream of up to [limit] new male users in a specific language bucket (or all).
  Stream<List<Map<String, dynamic>>> streamNewMales({
    String? femaleLanguage,
    int limit = 20,
  }) {
    final langKey = femaleLanguage != null ? bucketKeyFor(femaleLanguage) : 'all';
    final ref = newMalesBucketsRef.child(langKey).limitToLast(limit);
    return ref.onValue.map((event) {
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

  /// Fetch up to [limit] new males with language bucketing & fallback seeding.
  /// Prioritizes candidates matching [femaleLanguage], and supplements with other languages
  /// to ensure 20 users are always available.
  Future<List<Map<String, dynamic>>> fetchNewMalesWithFallback({
    String? femaleLanguage,
    int limit = 20,
  }) async {
    final List<Map<String, dynamic>> result = [];
    final targetLangKey = femaleLanguage != null ? bucketKeyFor(femaleLanguage) : null;

    // 1. Try language bucket first (if specified)
    if (targetLangKey != null && targetLangKey.isNotEmpty) {
      try {
        final snap = await newMalesBucketsRef.child(targetLangKey).limitToLast(limit).get();
        if (snap.exists && snap.value != null) {
          final map = Map<String, dynamic>.from(snap.value as Map);
          for (var entry in map.entries) {
            if (entry.value is Map) {
              final item = Map<String, dynamic>.from(entry.value as Map);
              item['uid'] = entry.key;
              if (await isEligible(entry.key)) {
                result.add(item);
              }
            }
          }
        }
      } catch (e) {
        debugPrint('[NewMaleService] Error querying language bucket [$targetLangKey]: $e');
      }
    }

    // 2. Supplement from global 'all' bucket or master pool if fewer than limit
    if (result.length < limit) {
      try {
        final snap = await newMalesBucketsRef.child('all').limitToLast(limit * 2).get();
        if (snap.exists && snap.value != null) {
          final map = Map<String, dynamic>.from(snap.value as Map);
          for (var entry in map.entries) {
            if (result.length >= limit) break;
            final uid = entry.key;
            if (result.any((u) => u['uid'] == uid)) continue;

            if (entry.value is Map) {
              final item = Map<String, dynamic>.from(entry.value as Map);
              item['uid'] = uid;
              if (await isEligible(uid)) {
                result.add(item);
              }
            }
          }
        }
      } catch (e) {
        debugPrint('[NewMaleService] Error querying all bucket: $e');
      }
    }

    // 3. Fallback auto-seeding from existing users in UserDatabaseService
    if (result.length < limit) {
      try {
        final existingSnap = await UserDatabaseService.instance.usersRef
            .limitToLast(limit * 4)
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
              final userLang = (uData['primaryLanguage'] ?? uData['language'] ?? uData['languages'] ?? 'Hindi').toString();
              final userLangKey = bucketKeyFor(userLang);

              final item = <String, dynamic>{
                'uid': uid,
                'nickname': uData['nickname'] ?? uData['name'] ?? 'User',
                'avatarUrl': uData['profileImageUrl'] ?? uData['avatarUrl'] ?? '',
                'avatarIndex': (uData['avatarIndex'] as num?)?.toInt() ?? 1,
                'language': userLang,
                'languageKey': userLangKey,
                'fcmToken': uData['fcmToken'] ?? '',
                'isOnline': true,
                'lastSeen': DateTime.now().millisecondsSinceEpoch,
              };
              result.add(item);

              // Seed into master pool and buckets on new RTDB asynchronously
              newMalesPoolRef.child(uid).set(item).catchError((_) {});
              newMalesBucketsRef.child(userLangKey).child(uid).set(item).catchError((_) {});
              newMalesBucketsRef.child('all').child(uid).set(item).catchError((_) {});
            }
          }
        }
      } catch (e) {
        debugPrint('[NewMaleService] Fallback seed error: $e');
      }
    }

    // Sort so exact language matches appear first, followed by others
    if (targetLangKey != null && targetLangKey.isNotEmpty) {
      result.sort((a, b) {
        final aMatch = bucketKeyFor(a['language'] as String?) == targetLangKey;
        final bMatch = bucketKeyFor(b['language'] as String?) == targetLangKey;
        if (aMatch && !bMatch) return -1;
        if (!aMatch && bMatch) return 1;
        return 0;
      });
    }

    return result;
  }

  /// Pick a random eligible male matching the female's language bucket (with fallback to all).
  Future<Map<String, dynamic>?> pickRandomMale(
    Iterable<String> excludedUids, {
    String? femaleLanguage,
  }) async {
    final excludedSet = excludedUids.toSet();
    final targetLangKey = femaleLanguage != null ? bucketKeyFor(femaleLanguage) : null;

    // 1. Try targeted language bucket first
    if (targetLangKey != null && targetLangKey.isNotEmpty) {
      try {
        final snap = await newMalesBucketsRef.child(targetLangKey).limitToLast(40).get();
        if (snap.exists && snap.value != null) {
          final map = Map<String, dynamic>.from(snap.value as Map);
          final candidates = <Map<String, dynamic>>[];
          for (var entry in map.entries) {
            final uid = entry.key;
            if (excludedSet.contains(uid)) continue;
            if (entry.value is Map) {
              final item = Map<String, dynamic>.from(entry.value as Map);
              item['uid'] = uid;
              if (await isEligible(uid)) {
                candidates.add(item);
              }
            }
          }
          if (candidates.isNotEmpty) {
            final rand = Random();
            final picked = candidates[rand.nextInt(candidates.length)];
            debugPrint('[NewMaleService] Picked language-matched candidate: ${picked['uid']} ($targetLangKey)');
            return picked;
          }
        }
      } catch (e) {
        debugPrint('[NewMaleService] Error reading language bucket for random call: $e');
      }
    }

    // 2. Fallback: pick from 'all' bucket or pool
    final fallbackList = await fetchNewMalesWithFallback(
      femaleLanguage: femaleLanguage,
      limit: 20,
    );
    final eligibleFallback = fallbackList.where((m) => !excludedSet.contains(m['uid'])).toList();
    if (eligibleFallback.isEmpty) return null;

    final rand = Random();
    return eligibleFallback[rand.nextInt(eligibleFallback.length)];
  }
}
