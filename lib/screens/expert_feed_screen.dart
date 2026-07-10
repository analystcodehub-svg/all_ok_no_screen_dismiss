import 'package:flutter/material.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:provider/provider.dart';
import '../providers/app_state.dart';
import '../models/female_expert.dart';
import 'matchmaking_screen.dart';
import 'wallet_recharge_screen.dart';
import 'hybrid_chat_screen.dart';
import '../widgets/expert_card.dart';
class ExpertFeedScreen extends StatefulWidget {
  const ExpertFeedScreen({Key? key}) : super(key: key);

  @override
  State<ExpertFeedScreen> createState() => _ExpertFeedScreenState();
}

class _ExpertFeedScreenState extends State<ExpertFeedScreen> {
  Future<List<Map<dynamic, dynamic>>>? _expertsFuture;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Fetch experts only once when the screen loads
    if (_expertsFuture == null) {
      _expertsFuture = _fetchExperts();
    }
  }

  Future<List<Map<dynamic, dynamic>>> _fetchExperts() async {
    String languageCode = Localizations.localeOf(context).languageCode;
    String bucket = 'hindi'; // Default bucket
    
    if (languageCode == 'pa') {
      bucket = 'punjabi';
    } else if (languageCode == 'hi') {
      bucket = 'hindi';
    }
    
    const int limit = 150; // Hardcoded Smart Limit
    
    final db = FirebaseDatabase.instanceFor(
      app: FirebaseDatabase.instance.app,
      databaseURL: 'https://zegochat-c44b0.asia-southeast1.firebasedatabase.app',
    );
    final snapshot = await db
        .ref('queues/female_$bucket')
        .orderByChild('totalTalkSeconds')
        .limitToLast(limit)
        .get();

    List<Map<dynamic, dynamic>> expertList = [];
    if (snapshot.exists) {
      for (var child in snapshot.children) {
        if (child.value != null) {
          Map<dynamic, dynamic> data = {};
          
          if (child.value is Map) {
            data = Map<dynamic, dynamic>.from(child.value as Map);
          } else {
            // Real experts set from MatchmakingService just put a ServerValue.timestamp
            data['timestamp'] = child.value;
            data['nickname'] = 'Expert'; // Fallback if no nickname is in the payload
          }
          
          data['id'] = child.key;
          data['language'] = bucket == 'punjabi' ? 'Punjabi' : 'Hindi';
          
          expertList.add(data);
        }
      }
    }
    
    // Fetch isOnline status for all fetched experts in parallel
    await Future.wait(expertList.map((expert) async {
      try {
        final statusEvent = await db.ref('status/${expert['id']}/isOnline').once();
        expert['isOnline'] = statusEvent.snapshot.value == true;
      } catch (e) {
        expert['isOnline'] = true; // Fallback
      }
    }));

    // Client-side shuffle in RAM to randomize the top 150
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
              
              return ExpertCard(
                expertId: expert['id'] ?? '',
                nickname: nickname,
                language: language,
                isOnline: isOnline,
                onCallTap: () async {
                  debugPrint('Call button tapped for ${expert['nickname']} with ID ${expert['id']}');
                  final expertId = expert['id'];
                  try {
                    final doc = await FirebaseFirestore.instance.collection('experts').doc(expertId).get();
                    if (doc.exists && context.mounted) {
                      final data = doc.data() as Map<String, dynamic>;
                      final expertObj = FemaleExpert(
                        id: doc.id,
                        nickname: data['nickname'] ?? nickname,
                        pricePerMin: (data['pricePerMin'] as num?)?.toInt() ?? 5,
                        languages: data['languages'] ?? 'Hindi',
                        rating: (data['rating'] ?? 4.5).toDouble(),
                        isOnline: true,
                      );
                      
                      final appState = context.read<AppState>();
                      final balance = appState.walletBalance;
                      final hasUsedFreeCall = appState.hasUsedFreeCall;
                      
                      if (false) { // TODO: Disabled payment gateway and free call logic for now
                        showDialog(
                          context: context,
                          builder: (context) => AlertDialog(
                            title: const Text('Insufficient Balance', style: TextStyle(fontWeight: FontWeight.bold)),
                            content: Text('Your wallet balance is ₹${balance.toStringAsFixed(2)}. You need at least ₹${expertObj.pricePerMin} to place a call.'),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(context),
                                child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
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
                      } else {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => MatchmakingScreen(
                              requestedExpert: expertObj,
                              isRandomMode: false,
                            ),
                          ),
                        );
                      }
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
                  String myUid = appState.selectedGender == 'Female' ? appState.uid : appState.mobileNumber;
                  if (myUid.isEmpty) myUid = appState.mobileNumber;
                  if (myUid.isEmpty) myUid = "test_mobile";
                  
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => HybridChatScreen(
                        myUid: myUid,
                        otherUid: expert['id'],
                        otherUserName: nickname,
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
