import 'dart:async';

import 'package:flutter/widgets.dart';

import '../core/state/app_cubit.dart';

/// Logs the user out after a while without touching the screen, and when the
/// app stayed in the background for that long, so a phone left on the counter
/// does not stay open.
class IdleGuard extends StatefulWidget {
  const IdleGuard({
    super.key,
    required this.cubit,
    required this.child,
    this.timeout = const Duration(minutes: 15),
  });

  final AppCubit cubit;
  final Widget child;
  final Duration timeout;

  @override
  State<IdleGuard> createState() => _IdleGuardState();
}

class _IdleGuardState extends State<IdleGuard> with WidgetsBindingObserver {
  Timer? _timer;
  StreamSubscription<AppState>? _subscription;
  DateTime? _backgroundAt;
  bool _wasAuthenticated = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _wasAuthenticated = widget.cubit.state.isAuthenticated;
    _subscription = widget.cubit.stream.listen((state) {
      if (state.isAuthenticated != _wasAuthenticated) {
        _wasAuthenticated = state.isAuthenticated;
        _restart();
      }
    });
    _restart();
  }

  void _restart() {
    _timer?.cancel();
    if (!widget.cubit.state.isAuthenticated) return;
    _timer = Timer(widget.timeout, _lock);
  }

  void _lock() {
    if (widget.cubit.state.isAuthenticated) {
      widget.cubit.logout();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      _backgroundAt = DateTime.now();
    } else if (state == AppLifecycleState.resumed) {
      final left = _backgroundAt;
      _backgroundAt = null;
      if (left != null && DateTime.now().difference(left) >= widget.timeout) {
        _lock();
      } else {
        _restart();
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _subscription?.cancel();
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (_) => _restart(),
      onPointerMove: (_) => _restart(),
      child: widget.child,
    );
  }
}
