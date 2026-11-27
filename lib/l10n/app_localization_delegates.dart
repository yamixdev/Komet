import 'package:material_ui/material_ui.dart';

import 'app_localizations.dart';

const appLocalizationDelegates = [
  AppLocalizations.delegate,
  ...GlobalMaterialLocalizations.delegates,
];

Widget withLegacyMaterial(Widget child) {
  // ignore: deprecated_member_use
  return MaterialUiCompatibilityBridge(child: child);
}
