import 'package:flutter/widgets.dart';

import 'app/app.dart';
import 'app/app_dependencies.dart';
import 'app/recovery_app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    final dependencies = await AppDependencies.create();
    runApp(MiniPosRoot(dependencies: dependencies));
  } catch (e) {
    runApp(RecoveryApp(error: e));
  }
}
