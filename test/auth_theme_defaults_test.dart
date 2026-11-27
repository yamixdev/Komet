import 'package:flutter_test/flutter_test.dart';
import 'package:komet/core/config/app_amoled.dart';
import 'package:komet/core/config/app_theme_mode.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('the default follows a dark system without AMOLED', (
    tester,
  ) async {
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
    addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
    SharedPreferences.setMockInitialValues({});

    expect(await AppThemeModeConfig.load(), AppThemeMode.system);
    expect(await AppAmoled.load(), isFalse);
  });

  test('loads an explicit theme and AMOLED preference independently', () async {
    SharedPreferences.setMockInitialValues({
      AppThemeModeConfig.prefKey: 'light',
      AppAmoled.prefKey: true,
    });

    expect(await AppThemeModeConfig.load(), AppThemeMode.light);
    expect(await AppAmoled.load(), isTrue);
  });
}
