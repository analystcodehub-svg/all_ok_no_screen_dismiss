import 'dart:async';
import 'dart:math';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/app_state.dart';
import '../models/female_expert.dart';
import 'matchmaking_screen.dart';
import 'hybrid_chat_screen.dart';
import '../widgets/expert_card.dart';
import 'wallet_recharge_screen.dart';
import '../services/user_database_service.dart';

class ExpertFeedScreen extends StatefulWidget {
  final ScrollController? scrollController;
  const ExpertFeedScreen({super.key, this.scrollController});

  @override
  State<ExpertFeedScreen> createState() => _ExpertFeedScreenState();
}

class _ExpertFeedScreenState extends State<ExpertFeedScreen> {
  StreamSubscription<DatabaseEvent>? _bucketSubscription;
  List<Map<dynamic, dynamic>> _displayExperts = [];
  bool _isLoading = true;
  String _displayLang = 'Hindi';

  // Progressive Streaming Pagination parameters (50 initially, +15 on scroll, max 100)
  static const int _initialCount = 50;
  static const int _batchSize = 15;
  static const int _maxCeiling = 100;

  int _visibleCount = _initialCount;
  bool _isLoadingMore = false;

  @override
  void initState() {
    super.initState();
    widget.scrollController?.addListener(_onScroll);
  }

  @override
  void didUpdateWidget(covariant ExpertFeedScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.scrollController != widget.scrollController) {
      oldWidget.scrollController?.removeListener(_onScroll);
      widget.scrollController?.addListener(_onScroll);
    }
  }

  void _onScroll() {
    if (widget.scrollController == null) return;
    final pos = widget.scrollController!.position;
    if (pos.pixels >= pos.maxScrollExtent - 300) {
      _loadMore();
    }
  }

  void _loadMore() {
    if (_isLoadingMore) return;
    final int currentTotal = _displayExperts.length < _maxCeiling
        ? _displayExperts.length
        : _maxCeiling;
    if (_visibleCount >= currentTotal) return;

    setState(() {
      _isLoadingMore = true;
    });

    Future.delayed(const Duration(milliseconds: 250), () {
      if (!mounted) return;
      setState(() {
        _visibleCount = (_visibleCount + _batchSize).clamp(0, _maxCeiling);
        _isLoadingMore = false;
      });
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_bucketSubscription == null) {
      _initBucketStream();
    }
  }

  Future<void> _initBucketStream() async {
    final appState = context.read<AppState>();
    String mobile = appState.uid.isNotEmpty ? appState.uid : appState.mobileNumber;
    String languageCode = Localizations.localeOf(context).languageCode;

    // 1. Male's language -> bucket key
    String language = '';
    try {
      final userData = await UserDatabaseService.instance.getUser(mobile);
      language = (userData?['primaryLanguage'] as String?) ?? '';
    } catch (e) {
      debugPrint('Error fetching primary language: $e');
    }
    if (language.trim().isEmpty) language = appState.primaryLanguage;
    if (language.trim().isEmpty && languageCode == 'pa') language = 'punjabi';
    final String bucket = UserDatabaseService.bucketKeyFor(language);
    _displayLang = bucket[0].toUpperCase() + bucket.substring(1);

    const int limit = 100; // Top 100 by totalTalkSeconds in this language bucket

    // 2. Real-time stream from Firebase RTDB
    final query = UserDatabaseService.instance.expertBucketsRef
        .child(bucket)
        .orderByChild('totalTalkSeconds')
        .limitToLast(limit);

    await _bucketSubscription?.cancel();
    _bucketSubscription = query.onValue.listen((event) {
      final snapshot = event.snapshot;
      final Map<String, Map<dynamic, dynamic>> incomingMap = {};

      if (snapshot.exists && snapshot.children.isNotEmpty) {
        for (var child in snapshot.children) {
          if (child.value is Map) {
            final data = Map<dynamic, dynamic>.from(child.value as Map);
            data['id'] = child.key;
            data['language'] = _displayLang;
            data['isOnline'] = true;
            incomingMap[child.key!] = data;
          }
        }
      }

      if (!mounted) return;

      setState(() {
        _isLoading = false;
        if (_displayExperts.isEmpty) {
          // Initial load: take all and randomize
          _displayExperts = incomingMap.values.toList()..shuffle();
        } else {
          // Live incremental sync:
          // 1. Remove experts who went offline
          _displayExperts.removeWhere((exp) => !incomingMap.containsKey(exp['id']));

          // 2. Update existing experts with fresh stats/avatars
          for (int i = 0; i < _displayExperts.length; i++) {
            final id = _displayExperts[i]['id'];
            if (incomingMap.containsKey(id)) {
              _displayExperts[i] = incomingMap[id]!;
            }
          }

          // 3. Add newly online experts at a randomized position for fair immediate exposure
          final existingIds = _displayExperts.map((e) => e['id']).toSet();
          final newExperts = incomingMap.values
              .where((e) => !existingIds.contains(e['id']))
              .toList()
            ..shuffle();

          final rand = Random();
          for (var newExp in newExperts) {
            final insertIndex = _displayExperts.isEmpty
                ? 0
                : rand.nextInt(_displayExperts.length + 1);
            _displayExperts.insert(insertIndex, newExp);
          }

          // Cap at 100
          if (_displayExperts.length > 100) {
            _displayExperts = _displayExperts.sublist(0, 100);
          }
        }
      });
    }, onError: (error) {
      debugPrint('Error listening to expert bucket: $error');
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    });
  }

  @override
  void dispose() {
    widget.scrollController?.removeListener(_onScroll);
    _bucketSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 32.0),
        child: Center(child: CircularProgressIndicator()),
      );
    }

    if (_displayExperts.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 32.0),
        child: Center(
          child: Text(
            'No experts available right now.',
            style: TextStyle(fontSize: 16, color: Colors.grey),
          ),
        ),
      );
    }

    final int currentVisibleTotal = _displayExperts.length < _visibleCount
        ? _displayExperts.length
        : (_visibleCount > _maxCeiling ? _maxCeiling : _visibleCount);
    final bool hasMoreToLoad = currentVisibleTotal < _displayExperts.length && currentVisibleTotal < _maxCeiling;
    final int totalListCount = currentVisibleTotal + (hasMoreToLoad ? 1 : 0);

    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: totalListCount,
      padding: const EdgeInsets.only(top: 8, bottom: 24),
      itemBuilder: (context, index) {
        if (index == currentVisibleTotal) {
          // Bottom loader tile for progressive streaming pagination
          if (!_isLoadingMore) {
            WidgetsBinding.instance.addPostFrameCallback((_) => _loadMore());
          }
          return Container(
            padding: const EdgeInsets.symmetric(vertical: 20),
            alignment: Alignment.center,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: const [
                SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF4F46E5)),
                ),
                SizedBox(width: 12),
                Text(
                  'Loading more experts...',
                  style: TextStyle(fontSize: 13, color: Color(0xFF64748B), fontWeight: FontWeight.w500),
                ),
              ],
            ),
          );
        }

        final expert = _displayExperts[index];
              final String nickname = expert['nickname'] ?? 'Unknown';
              final String language = expert['language'] ?? 'Hindi';
              final bool isOnline = expert['isOnline'] ?? true;
              final int age = expert['age'] ?? 22;
              final String? avatarUrl = expert['avatarUrl'];
              final int avatarIndex = expert['avatarIndex'] ?? 1;
              
              return ExpertCard(
                expertId: expert['id'] ?? '',
                nickname: nickname,
                language: language,
                isOnline: isOnline,
                age: age,
                avatarUrl: avatarUrl,
                avatarIndex: avatarIndex,
                onCallTap: () async {
                  debugPrint('Call button tapped for ${expert['nickname']} with ID ${expert['id']}');
                  
                  final appState = context.read<AppState>();
                  final balance = appState.coinBalance;
                  const overridePricePerMin = 4.0;
                  
                  if (balance < (overridePricePerMin * 10).toInt()) {
                    if (!context.mounted) return;
                    showDialog(
                      context: context,
                      builder: (context) => AlertDialog(
                        title: const Text(
                          'Insufficient Balance',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                        content: Text(
                          'Your balance is ₹${(balance / 10).toStringAsFixed(1)}. You need at least ₹$overridePricePerMin to place a call.',
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(context),
                            child: const Text(
                              'Cancel',
                              style: TextStyle(color: Colors.grey),
                            ),
                          ),
                          ElevatedButton(
                            onPressed: () {
                              Navigator.pop(context);
                              Navigator.push(context, MaterialPageRoute(builder: (context) => const WalletRechargeScreen()));
                            },
                            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF4F46E5)),
                            child: const Text('Recharge'),
                          ),
                        ],
                      ),
                    );
                    return;
                  }

                  final expertId = expert['id'];
                  try {
                    final data = await UserDatabaseService.instance.getExpert(expertId);
                    if (data != null && context.mounted) {
                      final expertObj = FemaleExpert(
                        id: expertId,
                        nickname: data['nickname'] ?? nickname,
                        pricePerMin: (data['pricePerMin'] as num?)?.toInt() ?? 4,
                        languages: data['languages'] ?? 'Hindi',
                        rating: (data['rating'] ?? 4.5).toDouble(),
                        isOnline: true,
                        age: (data['age'] as num?)?.toInt() ?? 22,
                        avatarUrl: data['profileImageUrl'] ?? data['avatarUrl'],
                        avatarIndex: (data['avatarIndex'] as num?)?.toInt() ?? 1,
                      );
                      
                      
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => MatchmakingScreen(
                            requestedExpert: expertObj,
                            isRandomMode: false,
                          ),
                        ),
                      );
                    } else if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Expert details not found in Firestore.')));
                    }
                  } catch (e) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
                    }
                  }
                },
                onChatTap: () {
                  final appState = context.read<AppState>();
                  final String myUid = appState.uid;
                  
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => HybridChatScreen(
                        myUid: myUid,
                        otherUid: expert['id'],
                        otherUserName: nickname,
                        otherUserAvatarUrl: expert['profileImageUrl'] ?? expert['avatarUrl'],
                        otherUserAvatarIndex: (expert['avatarIndex'] as num?)?.toInt() ?? 1,
                      ),
                    ),
                  );
                },
              );
            },
          );
  }
}
