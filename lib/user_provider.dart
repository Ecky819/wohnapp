import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'models/app_user.dart';
import 'repositories/user_repository.dart';

export 'repositories/user_repository.dart' show userRepositoryProvider;

final currentUserProvider = FutureProvider<AppUser?>((ref) async {
  final firebaseUser = FirebaseAuth.instance.currentUser;
  if (firebaseUser == null) return null;

  return ref.read(userRepositoryProvider).getOrCreate(firebaseUser);
});
