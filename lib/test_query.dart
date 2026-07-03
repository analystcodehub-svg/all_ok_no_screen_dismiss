import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  
  debugPrint("--- Fetching Experts from Firestore ---");
  final experts = await FirebaseFirestore.instance.collection('experts').get();
  for (var doc in experts.docs) {
    debugPrint("Expert ID: ${doc.id}, Nickname: ${doc.data()['nickname']}, CreatedAt: ${doc.data()['createdAt']}");
  }
  
  debugPrint("--- Fetching Users from Firestore ---");
  final users = await FirebaseFirestore.instance.collection('users').limit(10).get();
  for (var doc in users.docs) {
    debugPrint("User ID: ${doc.id}, Name: ${doc.data()['name']}, Role: ${doc.data()['role']}");
  }
  
  // We can't easily query RTDB here without setting up the specific app instance URL, 
  // but let's just see Firestore first.
}
