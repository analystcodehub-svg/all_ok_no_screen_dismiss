import 'package:flutter/material.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:provider/provider.dart';
import '../providers/app_state.dart';
import '../models/female_expert.dart';
import 'matchmaking_screen.dart';
import 'hybrid_chat_screen.dart';
import '../widgets/expert_card.dart';
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
    String mobile = appState.mobileNumber.isNotEmpty ? appState.mobileNumber : "test_mobile";
    String languageCode = Localizations.localeOf(context).languageCode;

    String bucket = 'hindi'; // Default bucket
    
    // First try to get from Firestore user profile
    try {
      final docSnap = await FirebaseFirestore.instance.collection('users').doc(mobile).get();
      if (docSnap.exists && docSnap.data() != null) {
        String lang = (docSnap.data()!['primaryLanguage'] as String?)?.toLowerCase() ?? '';
        if (lang.isNotEmpty) {
          if (lang == 'english') {
            bucket = 'english';
          } else if (lang == 'punjabi') {
            bucket = 'punjabi';
          } else if (lang == 'bengali') {
            bucket = 'bengali';
          } else if (lang == 'marathi') {
            bucket = 'marathi';
          } else if (lang == 'gujarati') {
            bucket = 'gujarati';
          } else if (lang == 'tamil') {
            bucket = 'tamil';
          } else if (lang == 'telugu') {
            bucket = 'telugu';
          } else if (lang == 'kannada') {
            bucket = 'kannada';
          } else if (lang == 'malayalam') {
            bucket = 'malayalam';
          } else {
            bucket = 'hindi';
          }
        }
      }
    } catch (e) {
      debugPrint('Error fetching primary language: $e');
    }

    // Fallback to device locale if bucket is still hindi and we want to check locale
    if (bucket == 'hindi') {
      if (languageCode == 'pa') {
        bucket = 'punjabi';
      }
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
          
          // Capitalize first letter for display
          String displayLang = bucket.isEmpty ? 'Hindi' : bucket[0].toUpperCase() + bucket.substring(1);
          data['language'] = displayLang;
          
          expertList.add(data);
        }
      }
    }
    
    // Fetch isOnline status and fallback nickname for all fetched experts in parallel
    await Future.wait(expertList.map((expert) async {
      try {
        final statusEvent = await db.ref('status/${expert['id']}/isOnline').once();
        expert['isOnline'] = statusEvent.snapshot.value == true;
        
        // Fallback for nickname if not present in RTDB (e.g. older expert app versions)
        if (expert['nickname'] == null || expert['nickname'] == 'Unknown' || expert['nickname'] == 'Expert') {
          final doc = await FirebaseFirestore.instance.collection('experts').doc(expert['id']).get();
          if (doc.exists && doc.data() != null) {
             final data = doc.data()!;
             expert['nickname'] = data['nickname'] ?? data['name'] ?? 'Expert';
          }
        }
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
