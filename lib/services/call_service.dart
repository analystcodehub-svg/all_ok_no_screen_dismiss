import 'dart:async';
import 'package:firebase_database/firebase_database.dart';
import 'package:cloud_firestore/cloud_firestore.dart' hide Transaction;
import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

class CallService {
  final FirebaseDatabase _database = FirebaseDatabase.instanceFor(
    app: FirebaseDatabase.instance.app,
    databaseURL: 'https://zegochat-c44b0.asia-southeast1.firebasedatabase.app',
  );

  RTCPeerConnection? _peerConnection;
  MediaStream? _localStream;
  MediaStream? _remoteStream;

  // Active listeners/subscriptions for call room updates
  final List<StreamSubscription> _subscriptions = [];

  // Dynamic listeners that can be updated after startCall/acceptCall
  Function(MediaStream stream)? onRemoteStreamListener;
  Function()? onCallEndedListener;

  /// Update the active call callbacks dynamically
  void updateListeners({
    Function(MediaStream stream)? onRemoteStream,
    Function()? onCallEnded,
  }) {
    if (onRemoteStream != null) {
      onRemoteStreamListener = onRemoteStream;
    }
    if (onCallEnded != null) {
      onCallEndedListener = onCallEnded;
    }
  }

  // WebRTC ICE Configuration using Google's free STUN servers
  final Map<String, dynamic> _iceConfiguration = {
    'iceServers': [
      {
        'urls': [
          'stun:stun.l.google.com:19302',
          'stun:stun1.l.google.com:19302',
          'stun:stun2.l.google.com:19302',
          'stun:stun3.l.google.com:19302',
          'stun:stun4.l.google.com:19302',
        ]
      },
      {
        'urls': [
          'turn:openrelay.metered.ca:80',
          'turn:openrelay.metered.ca:443',
          'turn:openrelay.metered.ca:443?transport=tcp'
        ],
        'username': 'openrelayproject',
        'credential': 'openrelayproject'
      }
    ],
    'sdpSemantics': 'unified-plan'
  };

  // Getters
  RTCPeerConnection? get peerConnection => _peerConnection;
  MediaStream? get localStream => _localStream;
  MediaStream? get remoteStream => _remoteStream;

  /// Listen for incoming calls for an expert.
  /// Trigger [onCallReceived] when another user creates a call with status 'calling'.
  StreamSubscription<DatabaseEvent> listenForIncomingCalls({
    required String expertId,
    required Function(String callRoomId, String callerId) onCallReceived,
  }) {
    return _database
        .ref('calls')
        .orderByChild('receiverId')
        .equalTo(expertId)
        .onChildAdded
        .listen((event) {
      if (event.snapshot.value != null) {
        final data = Map<String, dynamic>.from(event.snapshot.value as Map);
        if (data['status'] == 'calling') {
          final callRoomId = event.snapshot.key!;
          final callerId = data['callerId'] ?? 'unknown';
          onCallReceived(callRoomId, callerId);
        }
      }
    }, onError: (e) {
      debugPrint('Error listening for incoming calls: $e');
    });
  }

  /// Caller (Male Caller) initiates the call
  Future<String> startCall({
    required String expertId,
    required String callerId,
    required Function(MediaStream stream) onRemoteStream,
    required Function() onCallEnded,
  }) async {
    onRemoteStreamListener = onRemoteStream;
    onCallEndedListener = onCallEnded;
    try {
      // 1. Initialize local media audio track
      _localStream = await navigator.mediaDevices.getUserMedia({
        'audio': true,
        'video': false,
      });

      // 2. Create peer connection
      _peerConnection = await createPeerConnection(_iceConfiguration);

      // 3. Add local track to connection
      _localStream!.getTracks().forEach((track) {
        _peerConnection!.addTrack(track, _localStream!);
      });

      // 4. Listen for remote track / audio streams
      _peerConnection!.onTrack = (RTCTrackEvent event) {
        if (event.streams.isNotEmpty) {
          _remoteStream = event.streams[0];
          onRemoteStreamListener?.call(_remoteStream!);
        }
      };
      _peerConnection!.onAddStream = (MediaStream stream) {
        _remoteStream = stream;
        onRemoteStreamListener?.call(_remoteStream!);
      };

      // 5. Create call document in RTDB
      final DatabaseReference roomRef = _database.ref('calls').push();
      final String roomId = roomRef.key!;

      // 6. Handle local ICE candidates and upload them
      _peerConnection!.onIceCandidate = (RTCIceCandidate candidate) {
        if (candidate.candidate != null) {
          roomRef.child('callerCandidates').push().set({
            'candidate': candidate.candidate,
            'sdpMid': candidate.sdpMid,
            'sdpMLineIndex': candidate.sdpMLineIndex,
          });
        }
      };

      // 7. Generate SDP Offer
      final RTCSessionDescription offer = await _peerConnection!.createOffer();
      await _peerConnection!.setLocalDescription(offer);

      // 8. Upload SDP Offer to call document
      await roomRef.set({
        'offer': {
          'sdp': offer.sdp,
          'type': offer.type,
        },
        'callerId': callerId,
        'receiverId': expertId,
        'status': 'calling',
      });

      bool remoteDescriptionSet = false;
      final List<RTCIceCandidate> pendingRemoteCandidates = [];

      // 9. Subscribe to call document updates to catch SDP Answer
      final roomSub = roomRef.onValue.listen((event) async {
        if (event.snapshot.value == null) {
          onCallEndedListener?.call();
          return;
        }

        final data = Map<String, dynamic>.from(event.snapshot.value as Map);

        // Check if call was ended remotely
        if (data['status'] == 'ended') {
          onCallEndedListener?.call();
          return;
        }

        // Set Remote Description when answer is received
        if (data['answer'] != null && !remoteDescriptionSet) {
          remoteDescriptionSet = true;
          final answerMap = Map<String, dynamic>.from(data['answer']);
          final description = RTCSessionDescription(
            answerMap['sdp'],
            answerMap['type'],
          );
          await _peerConnection!.setRemoteDescription(description);

          // Add all queued remote candidates
          for (var candidate in pendingRemoteCandidates) {
            await _peerConnection!.addCandidate(candidate);
          }
          pendingRemoteCandidates.clear();
        }
      });
      _subscriptions.add(roomSub);

      // 10. Subscribe to remote ICE candidates (expertCandidates)
      final candidatesSub = roomRef
          .child('expertCandidates')
          .onChildAdded
          .listen((event) async {
        if (event.snapshot.value != null && _peerConnection != null) {
          final data = Map<String, dynamic>.from(event.snapshot.value as Map);
          final candidate = RTCIceCandidate(
            data['candidate'],
            data['sdpMid'],
            data['sdpMLineIndex'],
          );
          if (remoteDescriptionSet) {
            await _peerConnection!.addCandidate(candidate);
          } else {
            pendingRemoteCandidates.add(candidate);
          }
        }
      });
      _subscriptions.add(candidatesSub);

      return roomId;
    } catch (e) {
      debugPrint('Error starting WebRTC call: $e');
      await disposeCall();
      rethrow;
    }
  }

  /// Receiver (Female Expert) accepts the incoming call
  Future<void> acceptCall({
    required String callRoomId,
    required Function(MediaStream stream) onRemoteStream,
    required Function() onCallEnded,
  }) async {
    onRemoteStreamListener = onRemoteStream;
    onCallEndedListener = onCallEnded;
    try {
      final DatabaseReference roomRef = _database.ref('calls/$callRoomId');
      final roomSnapshot = await roomRef.get();
      if (!roomSnapshot.exists) {
        throw Exception('Call room not found');
      }

      final roomData = Map<String, dynamic>.from(roomSnapshot.value as Map);
      final offerMap = roomData['offer'] != null ? Map<String, dynamic>.from(roomData['offer']) : null;
      if (offerMap == null) {
        throw Exception('No SDP Offer found in room');
      }

      // 1. Initialize local media audio track
      _localStream = await navigator.mediaDevices.getUserMedia({
        'audio': true,
        'video': false,
      });

      // 2. Create peer connection
      _peerConnection = await createPeerConnection(_iceConfiguration);

      // 3. Add local track to connection
      _localStream!.getTracks().forEach((track) {
        _peerConnection!.addTrack(track, _localStream!);
      });

      // 4. Listen for remote track / audio streams
      _peerConnection!.onTrack = (RTCTrackEvent event) {
        if (event.streams.isNotEmpty) {
          _remoteStream = event.streams[0];
          onRemoteStreamListener?.call(_remoteStream!);
        }
      };
      _peerConnection!.onAddStream = (MediaStream stream) {
        _remoteStream = stream;
        onRemoteStreamListener?.call(_remoteStream!);
      };

      // 5. Handle local ICE candidates and upload them
      _peerConnection!.onIceCandidate = (RTCIceCandidate candidate) {
        if (candidate.candidate != null) {
          roomRef.child('expertCandidates').push().set({
            'candidate': candidate.candidate,
            'sdpMid': candidate.sdpMid,
            'sdpMLineIndex': candidate.sdpMLineIndex,
          });
        }
      };

      // 6. Set Remote Description (SDP Offer)
      final RTCSessionDescription remoteDescription = RTCSessionDescription(
        offerMap['sdp'],
        offerMap['type'],
      );
      await _peerConnection!.setRemoteDescription(remoteDescription);

      // 7. Generate SDP Answer
      final RTCSessionDescription answer = await _peerConnection!.createAnswer();
      await _peerConnection!.setLocalDescription(answer);

      // 8. Update RTDB document with SDP Answer and change status to connected
      await roomRef.update({
        'answer': {
          'sdp': answer.sdp,
          'type': answer.type,
        },
        'status': 'connected',
      });

      // 9. Subscribe to call document updates to monitor ended state
      final roomSub = roomRef.child('status').onValue.listen((event) {
        if (event.snapshot.value == null || event.snapshot.value == 'ended') {
          onCallEndedListener?.call();
        }
      });
      _subscriptions.add(roomSub);

      // 10. Subscribe to remote ICE candidates (callerCandidates)
      final candidatesSub = roomRef
          .child('callerCandidates')
          .onChildAdded
          .listen((event) {
        if (event.snapshot.value != null && _peerConnection != null) {
          final data = Map<String, dynamic>.from(event.snapshot.value as Map);
          _peerConnection!.addCandidate(
            RTCIceCandidate(
              data['candidate'],
              data['sdpMid'],
              data['sdpMLineIndex'],
            ),
          );
        }
      });
      _subscriptions.add(candidatesSub);
    } catch (e) {
      debugPrint('Error accepting WebRTC call: $e');
      await disposeCall();
      rethrow;
    }
  }

  /// Hangs up and clean up WebRTC resources and deletes the RTDB call document
  Future<void> endCall(String callRoomId) async {
    try {
      final DatabaseReference roomRef = _database.ref('calls/$callRoomId');
      
      // Update room status to ended and remove node
      await roomRef.update({'status': 'ended'});
      await roomRef.remove();
    } catch (e) {
      debugPrint('Error ending call document: $e');
    } finally {
      await disposeCall();
    }
  }

  /// Cleans up local media streams, peer connections, and cancels active listeners
  Future<void> disposeCall() async {
    // Cancel all RTDB stream subscriptions
    for (var sub in _subscriptions) {
      await sub.cancel();
    }
    _subscriptions.clear();

    // Stop and dispose local stream tracks
    if (_localStream != null) {
      for (var track in _localStream!.getTracks()) {
        await track.stop();
      }
      await _localStream!.dispose();
      _localStream = null;
    }

    _remoteStream = null;

    // Close peer connection
    if (_peerConnection != null) {
      await _peerConnection!.close();
      _peerConnection = null;
    }
  }

  /// Realtime Database Transaction to safely lock an expert before calling.
  /// Prevents race conditions if two users try to call simultaneously.
  Future<bool> lockExpertForCall(String expertId) async {
    try {
      final DatabaseReference ref = _database.ref("status/${expertId.toLowerCase()}");
      
      final TransactionResult result = await ref.runTransaction((Object? post) {
        if (post == null) {
          // If node doesn't exist, we can't lock. Return abort.
          return Transaction.abort();
        }

        Map<String, dynamic> data = Map<String, dynamic>.from(post as Map);
        
        // Read current status
        String status = data['status']?.toString() ?? 'online';
        bool isOnline = data['isOnline'] == true;
        
        // If expert is not online or already busy, abort
        if (!isOnline || status == 'busy' || status == 'in-call') {
          return Transaction.abort();
        }
        
        // Expert is available, apply lock
        data['status'] = 'busy';
        data['lastChanged'] = ServerValue.timestamp;
        
        return Transaction.success(data);
      });
      
      if (result.committed) {
        // Remove from experts queue so they stop receiving calls
        await _database.ref('experts_queue/${expertId.toLowerCase()}').remove();
      }
      
      return result.committed;
    } catch (e) {
      debugPrint('Error locking expert $expertId: $e');
      return false;
    }
  }

  /// Realtime Database Transaction to safely lock a user before calling.
  Future<bool> lockUserForCall(String userId) async {
    try {
      final DatabaseReference ref = _database.ref("status/$userId");
      
      final TransactionResult result = await ref.runTransaction((Object? post) {
        if (post == null) {
          return Transaction.success({
            'isOnline': false,
            'status': 'busy',
            'lastChanged': ServerValue.timestamp,
          });
        }

        Map<String, dynamic> data = Map<String, dynamic>.from(post as Map);
        String status = data['status']?.toString() ?? 'online';
        
        if (status == 'busy' || status == 'in-call') {
          return Transaction.abort();
        }
        
        data['status'] = 'busy';
        data['lastChanged'] = ServerValue.timestamp;
        
        return Transaction.success(data);
      });
      
      return result.committed;
    } catch (e) {
      debugPrint('Error locking user $userId: $e');
      return false;
    }
  }

  /// Reverts an expert's status to online and re-adds them to the experts queue if they were online.
  Future<void> unlockExpertFromCall(String expertId) async {
    try {
      final DatabaseReference ref = _database.ref("status/${expertId.toLowerCase()}");
      
      final snapshot = await ref.get();
      if (snapshot.exists) {
        final data = Map<String, dynamic>.from(snapshot.value as Map);
        if (data['isOnline'] == true) {
          // Revert to online
          await ref.update({
            'status': 'online',
            'lastChanged': ServerValue.timestamp,
          });
          
          // Verify if they are actually an expert before adding to queue
          final expertDoc = await FirebaseFirestore.instance.collection('experts').doc(expertId.toLowerCase()).get();
          if (expertDoc.exists) {
            await _database.ref('experts_queue/${expertId.toLowerCase()}').set({
              'expertId': expertId.toLowerCase(),
              'status': 'waiting',
              'timestamp': ServerValue.timestamp,
            });
          }
        } else {
          // They toggled offline during the call, just set status offline
          await ref.update({
            'status': 'offline',
            'lastChanged': ServerValue.timestamp,
          });
        }
      }
    } catch (e) {
      debugPrint('Error unlocking expert $expertId: $e');
    }
  }

  /// Reverts a user's status to online.
  Future<void> unlockUserFromCall(String userId) async {
    // Both users and experts use the same status node now. We can safely just call unlockExpertFromCall
    // because unlockExpertFromCall now checks Firestore before adding to the experts_queue!
    await unlockExpertFromCall(userId);
  }

  /// Cloud Firestore Transaction to safely deduct wallet balance.
  /// Validates sufficient balance and prevents concurrent deduction race conditions.
  Future<void> deductWalletBalance({required String userId, required double callCost}) async {
    final DocumentReference userRef = FirebaseFirestore.instance.collection('users').doc(userId);
    
    try {
      await FirebaseFirestore.instance.runTransaction((transaction) async {
        final snapshot = await transaction.get(userRef);
        
        if (!snapshot.exists) {
          throw Exception("User document does not exist.");
        }
        
        final data = snapshot.data() as Map<String, dynamic>?;
        double currentBalance = (data?['walletBalance'] as num?)?.toDouble() ?? 0.0;
        
        if (currentBalance < callCost) {
          throw Exception("Insufficient balance. Required: $callCost, Available: $currentBalance");
        }
        
        // Safe deduction within transaction lock
        double newBalance = currentBalance - callCost;
        transaction.update(userRef, {'walletBalance': newBalance});
      });
      
      debugPrint('Successfully deducted $callCost from user $userId. Transaction completed.');
    } catch (e) {
      debugPrint('Error deducting wallet balance for $userId: $e');
      rethrow; // Rethrow so the caller knows the transaction failed and can terminate the call
    }
  }
}
