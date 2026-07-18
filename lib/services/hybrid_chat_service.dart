import 'dart:async';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/foundation.dart';
import 'local_chat_database.dart';
import 'block_service.dart';

class HybridChatService {
  static final HybridChatService instance = HybridChatService._init();
  static String? activeChatRoomId;
  
  final FirebaseDatabase _database = FirebaseDatabase.instanceFor(
    app: FirebaseDatabase.instance.app,
    databaseURL: 'https://zegochat-c44b0.asia-southeast1.firebasedatabase.app',
  );

  StreamSubscription? _messagesSub;
  StreamSubscription? _acksSub;

  String? _initializedUid;

  HybridChatService._init();

  /// Start listening to temporary routing queues
  void initListeners(String myUid) {
    if (myUid.isEmpty) return; // Do not listen to root nodes

    // If already initialized for this UID, return
    if (_messagesSub != null && _initializedUid == myUid) return;
    
    // If initialized for a different UID, cancel old listeners
    dispose();
    
    _initializedUid = myUid;
    _listenToIncomingMessages(myUid);
    _listenToIncomingAcks(myUid);
  }

  void dispose() {
    _messagesSub?.cancel();
    _messagesSub = null;
    _acksSub?.cancel();
    _acksSub = null;
    _initializedUid = null;
  }

  /// Sends a message: Saves locally (status 1) and pushes to RTDB transit
  Future<void> sendMessage({
    required String roomId,
    required String senderUid,
    required String receiverUid,
    required String text,
  }) async {
    final msgId = _database.ref().push().key ?? DateTime.now().millisecondsSinceEpoch.toString();
    final timestamp = DateTime.now().millisecondsSinceEpoch;

    final message = {
      'msgId': msgId,
      'roomId': roomId,
      'senderId': senderUid,
      'text': text,
      'timestamp': timestamp,
      'status': 1, // 1: Sent
    };

    // 1. Save locally
    await LocalChatDatabase.instance.saveMessageLocally(message);

    // 2. Push to transit
    await _database.ref('transit/messages/$receiverUid/$msgId').set(message);
  }

  /// Manually mark an existing unread message as read (when user opens chat)
  Future<void> markAsRead(String msgId, String senderUid, String myUid) async {
    // 1. Update local status to 3
    await LocalChatDatabase.instance.updateMessageStatus(msgId, 3);
    
    // 2. Push Read ACK to sender
    await _pushAck(
      receiverUid: senderUid,
      msgId: msgId,
      status: 3,
    );
  }

  Future<void> _pushAck({required String receiverUid, required String msgId, required int status}) async {
    await _database.ref('transit/acks/$receiverUid/$msgId').set({
      'status': status,
      'timestamp': ServerValue.timestamp,
    });
  }

  void _listenToIncomingMessages(String myUid) {
    _messagesSub = _database.ref('transit/messages/$myUid').onChildAdded.listen((event) async {
      if (event.snapshot.value == null) return;

      final data = Map<String, dynamic>.from(event.snapshot.value as Map);
      final msgId = data['msgId'] as String;
      final roomId = data['roomId'] as String;
      final senderId = data['senderId'] as String;

      // Ensure we immediately delete from RTDB to maintain zero storage cost
      await event.snapshot.ref.remove();

      // Check if this sender is blocked
      if (BlockService.instance.isBlocked(senderId)) {
        debugPrint('Blocked message dropped from: $senderId');
        return; // Drop the message entirely
      }

      // Determine status based on active screen
      int localStatus = 2; // Default to delivered
      if (activeChatRoomId == roomId) {
        localStatus = 3; // Read immediately
        await _pushAck(receiverUid: senderId, msgId: msgId, status: 3);
      } else {
        await _pushAck(receiverUid: senderId, msgId: msgId, status: 2);
      }

      // Save to local SQLite
      data['status'] = localStatus;
      await LocalChatDatabase.instance.saveMessageLocally(data);
    }, onError: (e) {
      debugPrint('Error listening to incoming messages: $e');
    });
  }

  void _listenToIncomingAcks(String myUid) {
    _acksSub = _database.ref('transit/acks/$myUid').onChildAdded.listen((event) async {
      if (event.snapshot.value == null) return;

      final data = Map<String, dynamic>.from(event.snapshot.value as Map);
      final msgId = event.snapshot.key!;
      final newStatus = (data['status'] as num).toInt();

      // Ensure immediate deletion
      await event.snapshot.ref.remove();

      // Update local message status (e.g. from 1 to 2, or 2 to 3)
      await LocalChatDatabase.instance.updateMessageStatus(msgId, newStatus);
    }, onError: (e) {
      debugPrint('Error listening to incoming ACKs: $e');
    });
  }
}
