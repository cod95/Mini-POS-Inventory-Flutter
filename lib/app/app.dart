import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import '../core/l10n/app_localizations.dart';
import '../core/state/app_cubit.dart';
import 'app_dependencies.dart';
import 'app_scope.dart';
import 'router/app_router.dart';
import 'theme/app_theme.dart';

class MiniPosRoot extends StatefulWidget {
  const MiniPosRoot({super.key, required this.dependencies});

  final AppDependencies dependencies;

  @override
  State<MiniPosRoot> createState() => _MiniPosRootState();
}

class _MiniPosRootState extends State<MiniPosRoot> {
  late final AppRouter _appRouter = AppRouter(widget.dependencies);

  @override
  void dispose() {
    widget.dependencies.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AppScope(
      dependencies: widget.dependencies,
      child: BlocProvider.value(
        value: widget.dependencies.appCubit,
        child: BlocBuilder<AppCubit, AppState>(
          builder: (context, state) {
            final locale = Locale(state.settings.language);
            return MaterialApp.router(
              title: 'Mini POS + Inventory',
              debugShowCheckedModeBanner: false,
              theme: AppTheme.light(),
              locale: locale,
              supportedLocales: AppLocalizations.supportedLocales,
              localizationsDelegates: const [
                AppLocalizations.delegate,
                GlobalMaterialLocalizations.delegate,
                GlobalWidgetsLocalizations.delegate,
                GlobalCupertinoLocalizations.delegate,
              ],
              routerConfig: _appRouter.router,
            );
          },
        ),
      ),
    );
  }
}
