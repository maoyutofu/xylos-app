import 'package:flutter/material.dart';

import 'app_version.dart';
import 'ui/home_page.dart';

const kAppButtonRadius = 4.0;
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
  const XylosApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Xylos ${AppVersion.version}',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF1F7A68),
          brightness: Brightness.light,
        ),
        fontFamily: 'Microsoft YaHei UI',
        fontFamilyFallback: kAppFontFamilyFallback,
        useMaterial3: true,
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(kAppButtonRadius),
            ),
          ),
        ),
        textButtonTheme: TextButtonThemeData(
          style: TextButton.styleFrom(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(kAppButtonRadius),
            ),
          ),
        ),
        iconButtonTheme: IconButtonThemeData(
          style: IconButton.styleFrom(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(kAppButtonRadius),
            ),
          ),
        ),
        segmentedButtonTheme: SegmentedButtonThemeData(
          style: ButtonStyle(
            shape: WidgetStatePropertyAll(
              RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(kAppButtonRadius),
              ),
            ),
          ),
        ),
      ),
      home: const HomePage(),
    );
  }
}
