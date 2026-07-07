import 'package:flutter/material.dart';
import 'package:firebase_database/firebase_database.dart';
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
    
    final snapshot = await FirebaseDatabase.instance
        .ref('queues/$bucket')
        .orderByChild('totalTalkSeconds')
        .limitToLast(limit)
        .get();

    List<Map<dynamic, dynamic>> expertList = [];
    if (snapshot.exists) {
      for (var child in snapshot.children) {
        if (child.value != null) {
          Map<dynamic, dynamic> data = Map<dynamic, dynamic>.from(child.value as Map);
          data['id'] = child.key;
          expertList.add(data);
        }
      }
    }
    
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
              
              return ExpertCard(
                nickname: nickname,
                onCallTap: () {
                  // Placeholder for call routing logic
                  debugPrint('Call button tapped for ${expert['nickname']} with ID ${expert['id']}');
                },
              );
            },
          );
        },
      );
  }
}
