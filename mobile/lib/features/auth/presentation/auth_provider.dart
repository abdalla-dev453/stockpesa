import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api.dart';
import '../../../core/storage/cart_store.dart';
import '../../dashboard/data/dashboard_repository.dart';

enum SessionStatus { loading, signedOut, signedIn }

class SessionState {
  const SessionState({required this.status, required this.onboardingComplete});
  final SessionStatus status;
  final bool onboardingComplete;

  SessionState copyWith({SessionStatus? status, bool? onboardingComplete}) =>
      SessionState(
        status: status ?? this.status,
        onboardingComplete: onboardingComplete ?? this.onboardingComplete,
      );
}

final sessionProvider = NotifierProvider<SessionController, SessionState>(
  SessionController.new,
);

class SessionController extends Notifier<SessionState> {
  @override
  SessionState build() {
    final subscription = sessionExpiredStream.listen((_) {
      CartStore().clearAll();
      ref.read(dashboardRepositoryProvider).clearCache();
      if (state.status != SessionStatus.signedOut) {
        state = state.copyWith(status: SessionStatus.signedOut);
      }
    });
    ref.onDispose(subscription.cancel);
    Future.microtask(restore);
    return const SessionState(
      status: SessionStatus.loading,
      onboardingComplete: false,
    );
  }

  Future<void> restore() async {
    final onboarded = await hasCompletedOnboarding();
    var signedIn = false;
    if (await hasSavedSession()) {
      try {
        await currentUser();
        signedIn = true;
      } catch (_) {
        await logout();
      }
    }
    state = SessionState(
      status: signedIn ? SessionStatus.signedIn : SessionStatus.signedOut,
      onboardingComplete: onboarded,
    );
  }

  Future<void> finishOnboarding() async {
    await completeOnboarding();
    state = state.copyWith(onboardingComplete: true);
  }

  Future<void> signedIn() async {
    await currentUser();
    state = state.copyWith(status: SessionStatus.signedIn);
  }

  Future<void> signOut() async {
    await logout();
    ref.read(dashboardRepositoryProvider).clearCache();
    state = state.copyWith(status: SessionStatus.signedOut);
  }
}
