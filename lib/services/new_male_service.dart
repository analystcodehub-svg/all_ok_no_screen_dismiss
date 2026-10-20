import 'dart:async';
import 'dart:math';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
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

  /// Master profile record of all male users on this isolated database
  DatabaseReference get maleUsersRef => db.ref('male_users');

  /// Master pool of all eligible new males
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

  /// Check whether a male user is eligible for the single-time 1-minute intro call:
  /// Must NOT have recharged, must NOT have attended a female call, and must NOT have used free intro record.
  Future<bool> isEligible(String maleUid) async {
    if (maleUid.isEmpty) return false;
    try {
      // 1. Check free intro record
      final snap = await freeIntroCallsRef.child(maleUid).get();
      if (snap.exists && snap.value != null) {
        final data = Map<String, dynamic>.from(snap.value as Map);
        if (data['used'] == true) {
          final duration = (data['durationSeconds'] as num?)?.toInt() ?? 0;
          if (duration >= 5) {
            return false;
          } else {
            // Self-healing: previous call attempt was never answered or dropped (< 5s), restore eligibility
            freeIntroCallsRef.child(maleUid).remove().catchError((_) {});
            maleUsersRef.child(maleUid).update({
              'hasAttendedCall': false,
              'isEligible': true,
            }).catchError((_) {});
          }
        }
      }

      // 2. Check male user profile status on new RTDB
      final userSnap = await maleUsersRef.child(maleUid).get();
      if (userSnap.exists && userSnap.value != null) {
        final uData = Map<String, dynamic>.from(userSnap.value as Map);
        if (uData['hasRecharged'] == true) return false;
        if (uData['hasAttendedCall'] == true) {
          final duration = (uData['durationSeconds'] as num?)?.toInt() ?? 0;
          if (duration >= 5) return false;
        }
        if (uData['isEligible'] == false) {
          final duration = (uData['durationSeconds'] as num?)?.toInt() ?? 0;
          if (duration >= 5 || uData['hasRecharged'] == true) return false;
        }
        final coins = (uData['coins'] as num? ?? uData['coinBalance'] as num? ?? 0).toInt();
        if (coins > 0) return false;
      }

      // 3. Check user_call_logs: user must NOT have had connected calls (duration >= 5s)
      try {
        final logsSnap = await UserDatabaseService.instance.userCallLogsRef.child(maleUid).limitToLast(5).get();
        if (logsSnap.exists && logsSnap.value != null) {
          final logsMap = logsSnap.value;
          if (logsMap is Map) {
            for (var val in logsMap.values) {
              if (val is Map) {
                final duration = (val['durationSeconds'] as num?)?.toInt() ?? 0;
                final status = val['status']?.toString();
                if (duration >= 5 || status == 'connected') {
                  return false;
                }
              }
            }
          }
        }
      } catch (_) {}

      return true;
    } catch (e) {
      debugPrint('[NewMaleService] Error checking eligibility for $maleUid: $e');
      return true;
    }
  }

  /// Mark the male user as having attended the female call.
  /// Instantly removes him from all language buckets and marks him permanently ineligible for free calls.
  Future<void> markCallAttended({
    required String maleUid,
    required String femaleUid,
    String? femaleName,
    int durationSeconds = 0,
    String? language,
  }) async {
    if (maleUid.isEmpty) return;
    try {
      await maleUsersRef.child(maleUid).update({
        'hasAttendedCall': true,
        'isEligible': false,
        'attendedAt': ServerValue.timestamp,
        'lastFemaleUid': femaleUid,
        'lastFemaleName': femaleName ?? 'Female Expert',
        'durationSeconds': durationSeconds,
      });

      await freeIntroCallsRef.child(maleUid).set({
        'used': true,
        'usedAt': ServerValue.timestamp,
        'femaleId': femaleUid,
        'femaleName': femaleName ?? 'Female Expert',
        'durationSeconds': durationSeconds,
      });

      // Remove from active discovery pool and language buckets immediately
      await newMalesPoolRef.child(maleUid).remove();
      if (language != null && language.isNotEmpty) {
        await newMalesBucketsRef.child(bucketKeyFor(language)).child(maleUid).remove();
      } else {
        try {
          final uSnap = await maleUsersRef.child(maleUid).get();
          if (uSnap.exists && uSnap.value is Map) {
            final uMap = Map<String, dynamic>.from(uSnap.value as Map);
            final lKey = uMap['languageKey'] as String? ?? bucketKeyFor(uMap['language'] as String?);
            if (lKey.isNotEmpty) {
              await newMalesBucketsRef.child(lKey).child(maleUid).remove();
            }
          }
        } catch (_) {}
      }
      await newMalesBucketsRef.child('all').child(maleUid).remove();
      debugPrint('[NewMaleService] Immediately removed $maleUid from bucket (call was attended).');
    } catch (e) {
      debugPrint('[NewMaleService] Error marking call attended: $e');
    }
  }

  /// Mark the male user as having recharged his wallet.
  /// Instantly removes him from buckets so he is not called for free intro calls.
  Future<void> markRecharged(String maleUid, {String? language}) async {
    if (maleUid.isEmpty) return;
    try {
      await maleUsersRef.child(maleUid).update({
        'hasRecharged': true,
        'isEligible': false,
        'rechargedAt': ServerValue.timestamp,
      });

      await newMalesPoolRef.child(maleUid).remove();
      if (language != null && language.isNotEmpty) {
        await newMalesBucketsRef.child(bucketKeyFor(language)).child(maleUid).remove();
      } else {
        try {
          final uSnap = await maleUsersRef.child(maleUid).get();
          if (uSnap.exists && uSnap.value is Map) {
            final uMap = Map<String, dynamic>.from(uSnap.value as Map);
            final lKey = uMap['languageKey'] as String? ?? bucketKeyFor(uMap['language'] as String?);
            if (lKey.isNotEmpty) {
              await newMalesBucketsRef.child(lKey).child(maleUid).remove();
            }
          }
        } catch (_) {}
      }
      await newMalesBucketsRef.child('all').child(maleUid).remove();
      debugPrint('[NewMaleService] Immediately removed $maleUid from bucket (wallet recharged).');
    } catch (e) {
      debugPrint('[NewMaleService] Error marking recharged: $e');
    }
  }

  /// Legacy helper for call completion
  Future<void> markFreeCallUsed({
    required String maleUid,
    required String femaleUid,
    required int durationSeconds,
    String? language,
    String? femaleName,
  }) async {
    await markCallAttended(
      maleUid: maleUid,
      femaleUid: femaleUid,
      femaleName: femaleName,
      durationSeconds: durationSeconds,
      language: language,
    );
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

      // 0. Write to master male profile record on isolated RTDB
      await maleUsersRef.child(uid).update({
        'uid': uid,
        'nickname': nickname.isNotEmpty ? nickname : 'User',
        'avatarUrl': avatarUrl ?? '',
        'avatarIndex': avatarIndex,
        'language': language.isNotEmpty ? language : 'Hindi',
        'languageKey': langKey,
        'fcmToken': fcmToken ?? '',
        'isOnline': isOnline,
        'lastSeen': ServerValue.timestamp,
        'isEligible': true,
      });

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

  /// Real-time stream of up to [limit] (default: 50) new male users from the bucket pool.
  /// - Automatically removes users in real-time when removed from the pool (call completed, recharged, offline).
  /// - Excludes users who completed 1-min free intro (hasAttendedCall / used == true).
  /// - Excludes users who are currently busy or in an active call (callStatus == 'busy' or 'ringing').
  /// - Randomizes the available pool (up to 2000 users) and returns the top [limit] users.
  Stream<List<Map<String, dynamic>>> streamNewMales({
    String? femaleLanguage,
    int limit = 50,
    int? randomSeed,
  }) {
    final targetLangKey = femaleLanguage != null && femaleLanguage.isNotEmpty
        ? bucketKeyFor(femaleLanguage)
        : null;

    final poolQuery = newMalesPoolRef.limitToLast(2000);

    return poolQuery.onValue.asyncMap((event) async {
      final List<Map<String, dynamic>> candidates = [];

      if (event.snapshot.exists && event.snapshot.value != null) {
        final rawMap = event.snapshot.value;
        if (rawMap is Map) {
          final entries = rawMap.entries.toList();
          for (var entry in entries) {
            final uid = entry.key?.toString() ?? '';
            if (uid.isEmpty) continue;
            if (entry.value is! Map) continue;

            final user = Map<String, dynamic>.from(entry.value as Map);
            user['uid'] = uid;

            // 1. Exclude if user has completed intro call or attended call
            if (user['hasAttendedCall'] == true || user['isEligible'] == false) {
              continue;
            }

            // 2. Exclude if currently in call or busy
            final callStatus = user['callStatus']?.toString().toLowerCase();
            if (callStatus == 'busy' || callStatus == 'ringing' || callStatus == 'locked') {
              continue;
            }

            // 3. Exclude if recharged
            if (user['hasRecharged'] == true) {
              continue;
            }

            candidates.add(user);
          }
        }
      }

      // If pool has fewer than 10 candidates, seed in background asynchronously
      if (candidates.length < 10) {
        fetchNewMalesWithFallback(femaleLanguage: femaleLanguage, limit: 50).catchError((_) => <Map<String, dynamic>>[]);
      }

      if (candidates.isEmpty) {
        return <Map<String, dynamic>>[];
      }

      // 4. Randomize across the full pool
      final rand = randomSeed != null ? Random(randomSeed) : Random();
      candidates.shuffle(rand);

      // 5. Prioritize language matching if specified, while maintaining random distribution
      if (targetLangKey != null && targetLangKey.isNotEmpty) {
        final matches = candidates.where((c) {
          final lKey = (c['languageKey'] ?? bucketKeyFor(c['language'] as String?))?.toString();
          return lKey == targetLangKey;
        }).toList();

        final others = candidates.where((c) {
          final lKey = (c['languageKey'] ?? bucketKeyFor(c['language'] as String?))?.toString();
          return lKey != targetLangKey;
        }).toList();

        final combined = [...matches, ...others];
        return combined.take(limit).toList();
      }

      return candidates.take(limit).toList();
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

    // 3. Fallback from male_users records strictly on this isolated database (1e689)
    if (result.length < limit) {
      try {
        final existingSnap = await maleUsersRef
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
              final userLang = (uData['language'] ?? uData['primaryLanguage'] ?? 'Hindi').toString();
              final userLangKey = bucketKeyFor(userLang);

              final item = <String, dynamic>{
                'uid': uid,
                'nickname': uData['nickname'] ?? 'User',
                'avatarUrl': uData['avatarUrl'] ?? '',
                'avatarIndex': (uData['avatarIndex'] as num?)?.toInt() ?? 1,
                'language': userLang,
                'languageKey': userLangKey,
                'fcmToken': uData['fcmToken'] ?? '',
                'isOnline': uData['isOnline'] ?? true,
                'lastSeen': uData['lastSeen'] ?? DateTime.now().millisecondsSinceEpoch,
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

    // 4. Supplementary Fallback: Master users from 4cbfb RTDB
    if (result.length < limit) {
      try {
        final masterSnap = await UserDatabaseService.instance.usersRef.limitToLast(limit * 3).get();
        if (masterSnap.exists && masterSnap.value != null) {
          final usersMap = Map<String, dynamic>.from(masterSnap.value as Map);
          for (var entry in usersMap.entries) {
            if (result.length >= limit) break;
            final uid = entry.key;
            if (result.any((u) => u['uid'] == uid)) continue;

            final isElig = await isEligible(uid);
            if (!isElig) continue;

            if (entry.value is Map) {
              final uData = Map<String, dynamic>.from(entry.value as Map);
              if (uData['gender'] != null && uData['gender'] != 'male') continue;
              final userLang = (uData['language'] ?? uData['primaryLanguage'] ?? 'Hindi').toString();
              final userLangKey = bucketKeyFor(userLang);

              final item = <String, dynamic>{
                'uid': uid,
                'nickname': uData['nickname'] ?? uData['name'] ?? 'User',
                'avatarUrl': uData['avatarUrl'] ?? '',
                'avatarIndex': (uData['avatarIndex'] as num?)?.toInt() ?? 1,
                'language': userLang,
                'languageKey': userLangKey,
                'fcmToken': uData['fcmToken'] ?? '',
                'isOnline': uData['isOnline'] ?? true,
                'lastSeen': uData['lastSeen'] ?? DateTime.now().millisecondsSinceEpoch,
              };
              result.add(item);

              // Seed into master pool and buckets on new RTDB (1e689) asynchronously
              maleUsersRef.child(uid).set(item).catchError((_) {});
              newMalesPoolRef.child(uid).set(item).catchError((_) {});
              newMalesBucketsRef.child(userLangKey).child(uid).set(item).catchError((_) {});
              newMalesBucketsRef.child('all').child(uid).set(item).catchError((_) {});
            }
          }
        }
      } catch (e) {
        debugPrint('[NewMaleService] Master database fallback error: $e');
      }
    }

    // 5. Supplementary Fallback: Firestore 'users' collection
    if (result.length < limit) {
      try {
        final querySnap = await FirebaseFirestore.instance.collection('users').limit(limit * 2).get();
        for (var doc in querySnap.docs) {
          if (result.length >= limit) break;
          final uid = doc.id;
          if (result.any((u) => u['uid'] == uid)) continue;

          final uData = doc.data();
          if (uData['role'] == 'expert' || uData['gender'] == 'Female') continue;

          final isElig = await isEligible(uid);
          if (!isElig) continue;

          final userLang = (uData['language'] ?? uData['primaryLanguage'] ?? 'Hindi').toString();
          final userLangKey = bucketKeyFor(userLang);

          final item = <String, dynamic>{
            'uid': uid,
            'nickname': uData['nickname'] ?? uData['name'] ?? uData['displayName'] ?? 'User',
            'avatarUrl': uData['avatarUrl'] ?? '',
            'avatarIndex': (uData['avatarIndex'] as num?)?.toInt() ?? 1,
            'language': userLang,
            'languageKey': userLangKey,
            'fcmToken': uData['fcmToken'] ?? '',
            'isOnline': uData['isOnline'] ?? false,
            'lastSeen': DateTime.now().millisecondsSinceEpoch,
          };
          result.add(item);
        }
      } catch (e) {
        debugPrint('[NewMaleService] Firestore users fallback error: $e');
      }
    }

    // Sort: Online users first, users with FCM token first, then language match, then most recently seen
    result.sort((a, b) {
      final aOnline = a['isOnline'] == true ? 1 : 0;
      final bOnline = b['isOnline'] == true ? 1 : 0;
      if (aOnline != bOnline) return bOnline.compareTo(aOnline);

      final aHasFcm = (a['fcmToken']?.toString().trim().isNotEmpty ?? false) ? 1 : 0;
      final bHasFcm = (b['fcmToken']?.toString().trim().isNotEmpty ?? false) ? 1 : 0;
      if (aHasFcm != bHasFcm) return bHasFcm.compareTo(aHasFcm);

      if (targetLangKey != null && targetLangKey.isNotEmpty) {
        final aMatch = bucketKeyFor(a['language'] as String?) == targetLangKey ? 1 : 0;
        final bMatch = bucketKeyFor(b['language'] as String?) == targetLangKey ? 1 : 0;
        if (aMatch != bMatch) return bMatch.compareTo(aMatch);
      }

      final aLastSeen = (a['lastSeen'] as num?)?.toInt() ?? 0;
      final bLastSeen = (b['lastSeen'] as num?)?.toInt() ?? 0;
      return bLastSeen.compareTo(aLastSeen);
    });

    return result;
  }

  /// Pick a random eligible male matching the female's language bucket (with fallback to all).
  /// Mark a male user as unreachable (airplane mode, uninstalled, offline)
  /// so that subsequent matchmaking calls skip him in favor of online users.
  Future<void> markMaleUnreachable(String maleUid, {String? language}) async {
    if (maleUid.isEmpty) return;
    try {
      final updates = {
        'isOnline': false,
        'lastSeen': ServerValue.timestamp,
        'unreachableAt': ServerValue.timestamp,
      };
      await maleUsersRef.child(maleUid).update(updates);
      await newMalesPoolRef.child(maleUid).update(updates);
      await newMalesBucketsRef.child('all').child(maleUid).update(updates);
      if (language != null && language.isNotEmpty) {
        await newMalesBucketsRef.child(bucketKeyFor(language)).child(maleUid).update(updates);
      }
      debugPrint('[NewMaleService] Marked $maleUid unreachable/offline.');
    } catch (e) {
      debugPrint('[NewMaleService] Error marking male unreachable: $e');
    }
  }

  /// Pick a random eligible male matching the female's language bucket (with fallback to all).
  /// Excludes any UIDs in [excludedUids] (e.g. uninstalled or unreachable males),
  /// ensures candidates have valid FCM tokens, and prioritizes active online users.
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
              final fcmToken = (item['fcmToken'] as String?)?.trim() ?? '';
              if (fcmToken.isEmpty) continue; // Exclude users who cannot receive calls
              if (await isEligible(uid)) {
                candidates.add(item);
              }
            }
          }
          if (candidates.isNotEmpty) {
            // Prioritize active online users!
            final onlineList = candidates.where((c) => c['isOnline'] == true).toList();
            final pool = onlineList.isNotEmpty ? onlineList : candidates;
            final rand = Random();
            final picked = pool[rand.nextInt(pool.length)];
            debugPrint('[NewMaleService] Picked language-matched candidate: ${picked['uid']} ($targetLangKey, online: ${picked['isOnline']})');
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
    final eligibleFallback = fallbackList.where((m) {
      final uid = m['uid']?.toString() ?? '';
      final fcmToken = (m['fcmToken'] as String?)?.trim() ?? '';
      return uid.isNotEmpty && !excludedSet.contains(uid) && fcmToken.isNotEmpty;
    }).toList();
    if (eligibleFallback.isEmpty) return null;

    // Prioritize candidates who are online
    final onlinePool = eligibleFallback.where((m) => m['isOnline'] == true).toList();
    final candidatePool = onlinePool.isNotEmpty ? onlinePool : eligibleFallback;

    // Prioritize candidates matching female's language key if any
    final exactMatches = candidatePool.where(
      (m) => targetLangKey != null && bucketKeyFor(m['language'] as String?) == targetLangKey,
    ).toList();
    final finalPool = exactMatches.isNotEmpty ? exactMatches : candidatePool;

    final rand = Random();
    final picked = finalPool[rand.nextInt(finalPool.length)];
    debugPrint('[NewMaleService] Picked fallback candidate: ${picked['uid']} (online: ${picked['isOnline']})');
    return picked;
  }
}
