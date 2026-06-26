import 'package:flutter/material.dart';

import 'app_version.dart';
import 'services/account_store.dart';
import 'ui/app_theme.dart';
import 'ui/home_page.dart';

void main() {
  runApp(const XylosApp());
}

class XylosApp extends StatelessWidget {
  const XylosApp({super.key, this.store});

  final AccountStore? store;

  @override
  Widget build(BuildContext context) {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: kAppPrimaryColor,
      brightness: Brightness.light,
    ).copyWith(
      primary: kAppPrimaryColor,
      secondary: kAppPrimaryColor,
      tertiary: kAppPrimaryColor,
    );

    return MaterialApp(
      title: 'Xylos ${AppVersion.version}',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: colorScheme,
        fontFamily: 'Microsoft YaHei UI',
        fontFamilyFallback: kAppFontFamilyFallback,
        useMaterial3: true,
        extensions: const [XylosTheme.light],
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            backgroundColor: kAppPrimaryColor,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(kAppButtonRadius),
            ),
          ),
        ),
        textButtonTheme: TextButtonThemeData(
          style: TextButton.styleFrom(
            foregroundColor: kAppPrimaryColor,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(kAppButtonRadius),
            ),
          ),
        ),
        iconButtonTheme: IconButtonThemeData(
          style: IconButton.styleFrom(
            foregroundColor: kAppPrimaryColor,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(kAppButtonRadius),
            ),
          ),
        ),
        popupMenuTheme: PopupMenuThemeData(
          color: XylosTheme.light.menuSurface,
          surfaceTintColor: Colors.transparent,
          shadowColor: XylosTheme.light.shadow.withOpacity(0.08),
          elevation: 10,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(kAppButtonRadius),
            side: BorderSide(color: XylosTheme.light.moduleBorder),
          ),
          textStyle: const TextStyle(
            color: kAppTextColor,
            fontSize: 13,
            fontWeight: FontWeight.w500,
          ),
        ),
        cardTheme: CardTheme(
          color: XylosTheme.light.surface,
          shadowColor: Colors.transparent,
          surfaceTintColor: Colors.transparent,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(kAppButtonRadius),
            side: BorderSide(color: XylosTheme.light.moduleBorder),
          ),
          margin: EdgeInsets.zero,
        ),
        dialogTheme: DialogTheme(
          backgroundColor: XylosTheme.light.surface,
          surfaceTintColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(kAppButtonRadius),
            side: BorderSide(color: XylosTheme.light.moduleBorder),
          ),
        ),
        bottomSheetTheme: const BottomSheetThemeData(
          backgroundColor: Colors.transparent,
          surfaceTintColor: Colors.transparent,
        ),
        dividerTheme: DividerThemeData(
          color: XylosTheme.light.border,
          thickness: 1,
          space: 1,
        ),
        snackBarTheme: SnackBarThemeData(
          backgroundColor: XylosTheme.light.surface,
          contentTextStyle: const TextStyle(color: kAppTextColor),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(kAppButtonRadius),
            side: BorderSide(color: XylosTheme.light.moduleBorder),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: XylosTheme.light.menuSurface,
          focusedBorder: const OutlineInputBorder(
            borderSide: BorderSide(color: kAppPrimaryColor),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(kAppButtonRadius),
            borderSide: BorderSide(color: XylosTheme.light.moduleBorder),
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(kAppButtonRadius),
            borderSide: BorderSide(color: XylosTheme.light.moduleBorder),
          ),
        ),
        switchTheme: SwitchThemeData(
          thumbColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) {
              return kAppPrimaryColor;
            }
            return null;
          }),
          trackColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) {
              return kAppPrimaryColor.withOpacity(0.42);
            }
            return null;
          }),
        ),
        checkboxTheme: CheckboxThemeData(
          fillColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) {
              return kAppPrimaryColor;
            }
            return null;
          }),
        ),
        radioTheme: RadioThemeData(
          fillColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) {
              return kAppPrimaryColor;
            }
            return null;
          }),
        ),
        progressIndicatorTheme: const ProgressIndicatorThemeData(
          color: kAppPrimaryColor,
        ),
        textSelectionTheme: const TextSelectionThemeData(
          cursorColor: kAppPrimaryColor,
          selectionHandleColor: kAppPrimaryColor,
        ),
        segmentedButtonTheme: SegmentedButtonThemeData(
          style: ButtonStyle(
            foregroundColor: const WidgetStatePropertyAll(Colors.black),
            backgroundColor: WidgetStateProperty.resolveWith((states) {
              if (states.contains(WidgetState.selected)) {
                return kAppPrimaryColor;
              }
              return null;
            }),
            shape: WidgetStatePropertyAll(
              RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(kAppButtonRadius),
              ),
            ),
          ),
        ),
      ),
      home: HomePage(store: store),
    );
  }
}
