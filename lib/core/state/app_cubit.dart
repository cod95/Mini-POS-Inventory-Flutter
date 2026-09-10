import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../core/models/app_models.dart';
import '../../domain/entities/app_entities.dart';
import '../../domain/repositories/repositories.dart';

class AppState extends Equatable {
  const AppState({
    required this.settings,
    this.session,
    this.loading = false,
    this.error,
  });

  final AppSettingsModel settings;
  final AuthSession? session;
  final bool loading;
  final String? error;

  bool get isAuthenticated => session != null;

  AppState copyWith({
    AppSettingsModel? settings,
    AuthSession? session,
    bool clearSession = false,
    bool? loading,
    String? error,
    bool clearError = false,
  }) {
    return AppState(
      settings: settings ?? this.settings,
      session: clearSession ? null : session ?? this.session,
      loading: loading ?? this.loading,
      error: clearError ? null : error ?? this.error,
    );
  }

  static const initial = AppState(settings: AppSettingsModel.fallback);

  @override
  List<Object?> get props => [settings, session, loading, error];
}

class AppCubit extends Cubit<AppState> {
  AppCubit({
    required AuthRepository authRepository,
    required SettingsRepository settingsRepository,
  })  : _authRepository = authRepository,
        _settingsRepository = settingsRepository,
        super(AppState.initial);

  final AuthRepository _authRepository;
  final SettingsRepository _settingsRepository;

  Future<void> initialize() async {
    emit(state.copyWith(loading: true, clearError: true));
    try {
      final settings = await _settingsRepository.getSettings();
      emit(state.copyWith(settings: settings, loading: false));
    } catch (e) {
      emit(state.copyWith(loading: false, error: e.toString()));
    }
  }

  Future<bool> loginCashier(String pin) async {
    emit(state.copyWith(loading: true, clearError: true));
    final role = await _authRepository.loginWithPin(pin);
    if (role == null) {
      emit(state.copyWith(loading: false, error: 'Invalid credentials'));
      return false;
    }
    emit(
      state.copyWith(
        loading: false,
        session: AuthSession(role: role, loginTime: DateTime.now()),
      ),
    );
    return true;
  }

  Future<bool> loginAdmin(String password) async {
    emit(state.copyWith(loading: true, clearError: true));
    final role = await _authRepository.loginAsAdmin(password);
    if (role == null) {
      emit(state.copyWith(loading: false, error: 'Invalid credentials'));
      return false;
    }
    emit(
      state.copyWith(
        loading: false,
        session: AuthSession(role: role, loginTime: DateTime.now()),
      ),
    );
    return true;
  }

  Future<void> logout() async {
    await _authRepository.logout();
    emit(state.copyWith(clearSession: true));
  }

  Future<void> updateSettings(AppSettingsModel settings) async {
    emit(state.copyWith(loading: true, clearError: true));
    try {
      await _settingsRepository.updateSettings(settings);
      final saved = await _settingsRepository.getSettings();
      emit(state.copyWith(loading: false, settings: saved));
    } catch (e) {
      emit(state.copyWith(loading: false, error: e.toString()));
    }
  }

  Future<void> refreshSettings() async {
    final settings = await _settingsRepository.getSettings();
    emit(state.copyWith(settings: settings));
  }

  bool get isAdmin => state.session?.role == UserRole.admin;
}
