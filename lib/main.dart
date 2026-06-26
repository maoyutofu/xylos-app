import 'package:flutter/material.dart';

import 'app_version.dart';
import 'services/account_store.dart';
import 'ui/home_page.dart';

const kAppButtonRadius = 3.0;
const kAppPrimaryColor = Color(0xFF58C99F);
const kAppFontFamilyFallback = <String>[
  'Microsoft YaHei UI',
  'Microsoft YaHei',
  'PingFang SC',
  'Hiragino Sans GB',
  'Noto Sans CJK SC',
  'Noto Sans SC',
  'Source Han Sans SC',
  'WenQuanYi Micro Hei',
  'Arial',
];

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
          color: const Color(0xFFF8F9FA),
          surfaceTintColor: Colors.transparent,
          shadowColor: Colors.black.withOpacity(0.08),
          elevation: 10,
          menuPadding: const EdgeInsets.symmetric(vertical: 6),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(kAppButtonRadius),
            side: const BorderSide(color: Color(0xFFE4E6E8)),
          ),
          textStyle: const TextStyle(
            color: Color(0xFF111111),
            fontSize: 13,
            fontWeight: FontWeight.w500,
          ),
        ),
        inputDecorationTheme: const InputDecorationTheme(
          focusedBorder: OutlineInputBorder(
            borderSide: BorderSide(color: kAppPrimaryColor),
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
