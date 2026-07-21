import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();

  debugPrint('=== ALL EXPERTS IN FIRESTORE ===');
  final experts = await FirebaseFirestore.instance.collection('experts').get();
  for (var doc in experts.docs) {
    final data = doc.data();
    debugPrint('------ DOC: ${doc.id} ------');
    debugPrint('  nickname: ${data['nickname']}');
    debugPrint('  mobileNumber: ${data['mobileNumber']}');
    debugPrint('  isOnline: ${data['isOnline']}');
    debugPrint('  categories: ${data['categories']}');
    debugPrint('  ALL FIELDS: $data');
  }
  debugPrint('DONE');
}
