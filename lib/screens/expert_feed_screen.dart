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
  const ExpertFeedScreen({super.key});

  @override
  State<ExpertFeedScreen> createState() => _ExpertFeedScreenState();
}

class _ExpertFeedScreenState extends State<ExpertFeedScreen> {
  Future<List<Map<dynamic, dynamic>>>? _expertsFuture;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _expertsFuture ??= _fetchExperts();
  }

  Future<List<Map<dynamic, dynamic>>> _fetchExperts() async {
    final appState = context.read<AppState>();
    String mobile = appState.uid.isNotEmpty ? appState.uid : appState.mobileNumber;
    String languageCode = Localizations.localeOf(context).languageCode;

    // 1. Male's language -> bucket key (same normalisation the experts use).
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

    const int limit = 100; // Top 100 by totalTalkSeconds in this language bucket

    // 2. Read the language bucket from the NEW RTDB only:
    //    expert_buckets/<language>/<uid>  (online experts, ranked server-side
    //    by totalTalkSeconds via .indexOn).
    final snapshot = await UserDatabaseService.instance.expertBucketsRef
        .child(bucket)
        .orderByChild('totalTalkSeconds')
        .limitToLast(limit)
        .get();

    final String displayLang = bucket[0].toUpperCase() + bucket.substring(1);
    List<Map<dynamic, dynamic>> expertList = [];
    if (snapshot.exists) {
      for (var child in snapshot.children) {
        if (child.value is Map) {
          final data = Map<dynamic, dynamic>.from(child.value as Map);
          data['id'] = child.key;
          data['language'] = displayLang;
          data['isOnline'] = true; // bucket only holds online experts
          expertList.add(data);
        }
      }
    }

    // 3. Client-side shuffle in RAM to randomize the top 100
    expertList.shuffle();

    return expertList;
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Map<dynamic, dynamic>>>(
      future: _expertsFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return Center(
              child: Text(
                'Error loading experts',
                style: TextStyle(color: Colors.red[400]),
              ),
            );
          }

          final experts = snapshot.data;
          if (experts == null || experts.isEmpty) {
            return const Center(
              child: Text(
                'No experts available right now.',
                style: TextStyle(fontSize: 16, color: Colors.grey),
              ),
            );
          }

          return ListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: experts.length,
            padding: const EdgeInsets.only(top: 8, bottom: 24),
            itemBuilder: (context, index) {
              final expert = experts[index];
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
                  const overridePricePerMin = 3.0;
                  
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
                        pricePerMin: (data['pricePerMin'] as num?)?.toInt() ?? 5,
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
        },
      );
  }
}
