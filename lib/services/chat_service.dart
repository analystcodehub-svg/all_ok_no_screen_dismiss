import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

class ChatService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // Stream active chats for a user
  Stream<QuerySnapshot> getUserChats(String mobileNumber) {
    return _firestore
        .collection('chats')
        .where('participants', arrayContains: mobileNumber)
        .snapshots();
  }

  // Create or get an existing chat room between two users
  Future<String> createOrGetChatRoom(String user1, String user2) async {
    try {
      final query = await _firestore
          .collection('chats')
          .where('participants', arrayContains: user1)
          .get();

      // Find if there's a chat room that also contains user2
      for (var doc in query.docs) {
        List<dynamic> participants = doc['participants'];
        if (participants.contains(user2)) {
          return doc.id; // Return existing chat room ID
        }
      }

      // If no room exists, create a new one
      final newRoomRef = _firestore.collection('chats').doc();
      await newRoomRef.set({
        'participants': [user1, user2],
        'lastMessage': '',
      });
      return newRoomRef.id;
    } catch (e) {
      debugPrint('Error creating/getting chat room: $e');
      rethrow;
    }
  }
}
