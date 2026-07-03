import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  
  debugPrint('=== EXPERTS ===');
  final experts = await FirebaseFirestore.instance.collection('experts').get();
  for (var doc in experts.docs) {
    if (doc.id == 'gulabo' || doc.id == 'lovely') {
       debugPrint('Expert: ${doc.id} -> ${doc.data()}');
    }
  }
}
