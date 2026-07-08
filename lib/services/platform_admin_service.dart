import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Platform owner = the single hardcoded user who can manage tenant companies.
/// Locked to michael@nttas.com — mirrors the server-side `is_platform_owner()`
/// RLS helper so client and server agree on who is allowed.
const String kPlatformOwnerEmail = 'michael@nttas.com';

class PlatformAdminNotifier extends ValueNotifier<bool> {
  PlatformAdminNotifier() : super(false);

  Future<void> refresh() async {
    final sb = Supabase.instance.client;
    final email = sb.auth.currentUser?.email?.toLowerCase();
    value = email == kPlatformOwnerEmail;
  }

  void clear() {
    value = false;
  }
}

final platformAdminNotifier = PlatformAdminNotifier();
