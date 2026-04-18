import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'models/app_user.dart';
import 'repositories/user_repository.dart';

export 'repositories/user_repository.dart' show userRepositoryProvider;

final currentUserProvider = StreamProvider<AppUser?>((ref) {
  return FirebaseAuth.instance.authStateChanges().asyncMap((firebaseUser) async {
    if (firebaseUser == null) return null;
    return ref.read(userRepositoryProvider).getOrCreate(firebaseUser);
  });
});
