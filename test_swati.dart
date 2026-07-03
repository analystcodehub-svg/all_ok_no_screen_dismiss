import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  
  final snapshot = await FirebaseFirestore.instance.collection('experts').get();
  debugPrint('Total experts: ${snapshot.docs.length}');
  for (var doc in snapshot.docs) {
    debugPrint('Expert: ${doc.id}');
    debugPrint('  nickname: ${doc.data()['nickname']}');
    debugPrint('  isOnline: ${doc.data()['isOnline']}');
    debugPrint('  categories: ${doc.data()['categories']}');
  }
}
