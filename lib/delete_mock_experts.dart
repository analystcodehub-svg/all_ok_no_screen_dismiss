import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:jaimakali/models/female_expert.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();

  final mockNicknames = FemaleExpert.mockExperts.map((e) => e.nickname.toLowerCase()).toList();
  mockNicknames.add('soni kumari'); // Explicitly adding the one from Recents

  final collection = FirebaseFirestore.instance.collection('experts');
  
  for (final nickname in mockNicknames) {
    try {
      await collection.doc(nickname).delete();
      debugPrint('Deleted $nickname from Firestore');
    } catch (e) {
      debugPrint('Error deleting $nickname: $e');
    }
  }

  debugPrint('Cleanup complete!');
}
