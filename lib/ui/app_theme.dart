import 'package:flutter/material.dart';

const kAppButtonRadius = 3.0;
const kAppBrandColor = Color(0xFF4655C7);
const kAppBrandSoftColor = Color(0xFFEEF1FF);
const kAppPrimaryColor = Color(0xFF58C99F);
const kAppSuccessColor = kAppPrimaryColor;
const kAppBackgroundColor = Color(0xFFFFFFFF);
const kAppSurfaceColor = Color(0xFFFFFFFF);
const kAppPrimarySoftColor = Color(0xFFC9F3E3);
const kAppTextColor = Color(0xFF111111);
const kAppMutedColor = Color(0xFF6F716F);
const kAppBorderColor = Color(0xFFE9E7E0);
const kAppModuleBorderColor = Color(0xFFE4E6E8);
const kAppMenuSurfaceColor = Color(0xFFF8F9FA);
const kAppMenuTriggerSurfaceColor = Color(0xFFF6F7F8);
const kAppHoverSurfaceColor = Color(0xFFEAF8F2);
const kAppHighlightSurfaceColor = Color(0xFFD7F1E6);
const kAppSheetHandleColor = Color(0xFFD4D8DB);
const kAppDestructiveColor = Color(0xFFC84B4B);
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

@immutable
class XylosTheme extends ThemeExtension<XylosTheme> {
  const XylosTheme({
    required this.brand,
    required this.brandSoft,
    required this.background,
    required this.surface,
    required this.primarySoft,
    required this.text,
    required this.muted,
    required this.border,
    required this.moduleBorder,
    required this.menuSurface,
    required this.menuTriggerSurface,
    required this.hoverSurface,
    required this.highlightSurface,
    required this.sheetHandle,
    required this.success,
    required this.destructive,
    required this.shadow,
  });

  final Color brand;
  final Color brandSoft;
  final Color background;
  final Color surface;
  final Color primarySoft;
  final Color text;
  final Color muted;
  final Color border;
  final Color moduleBorder;
  final Color menuSurface;
  final Color menuTriggerSurface;
  final Color hoverSurface;
  final Color highlightSurface;
  final Color sheetHandle;
  final Color success;
  final Color destructive;
  final Color shadow;

  static const light = XylosTheme(
    brand: kAppBrandColor,
    brandSoft: kAppBrandSoftColor,
    background: kAppBackgroundColor,
    surface: kAppSurfaceColor,
    primarySoft: kAppPrimarySoftColor,
    text: kAppTextColor,
    muted: kAppMutedColor,
    border: kAppBorderColor,
    moduleBorder: kAppModuleBorderColor,
    menuSurface: kAppMenuSurfaceColor,
    menuTriggerSurface: kAppMenuTriggerSurfaceColor,
    hoverSurface: kAppHoverSurfaceColor,
    highlightSurface: kAppHighlightSurfaceColor,
    sheetHandle: kAppSheetHandleColor,
    success: kAppSuccessColor,
    destructive: kAppDestructiveColor,
    shadow: Colors.black,
  );

  @override
  XylosTheme copyWith({
    Color? brand,
    Color? brandSoft,
    Color? background,
    Color? surface,
    Color? primarySoft,
    Color? text,
    Color? muted,
    Color? border,
    Color? moduleBorder,
    Color? menuSurface,
    Color? menuTriggerSurface,
    Color? hoverSurface,
    Color? highlightSurface,
    Color? sheetHandle,
    Color? success,
    Color? destructive,
    Color? shadow,
  }) {
    return XylosTheme(
      brand: brand ?? this.brand,
      brandSoft: brandSoft ?? this.brandSoft,
      background: background ?? this.background,
      surface: surface ?? this.surface,
      primarySoft: primarySoft ?? this.primarySoft,
      text: text ?? this.text,
      muted: muted ?? this.muted,
      border: border ?? this.border,
      moduleBorder: moduleBorder ?? this.moduleBorder,
      menuSurface: menuSurface ?? this.menuSurface,
      menuTriggerSurface: menuTriggerSurface ?? this.menuTriggerSurface,
      hoverSurface: hoverSurface ?? this.hoverSurface,
      highlightSurface: highlightSurface ?? this.highlightSurface,
      sheetHandle: sheetHandle ?? this.sheetHandle,
      success: success ?? this.success,
      destructive: destructive ?? this.destructive,
      shadow: shadow ?? this.shadow,
    );
  }

  @override
  XylosTheme lerp(ThemeExtension<XylosTheme>? other, double t) {
    if (other is! XylosTheme) {
      return this;
    }
    return XylosTheme(
      brand: Color.lerp(brand, other.brand, t)!,
      brandSoft: Color.lerp(brandSoft, other.brandSoft, t)!,
      background: Color.lerp(background, other.background, t)!,
      surface: Color.lerp(surface, other.surface, t)!,
      primarySoft: Color.lerp(primarySoft, other.primarySoft, t)!,
      text: Color.lerp(text, other.text, t)!,
      muted: Color.lerp(muted, other.muted, t)!,
      border: Color.lerp(border, other.border, t)!,
      moduleBorder: Color.lerp(moduleBorder, other.moduleBorder, t)!,
      menuSurface: Color.lerp(menuSurface, other.menuSurface, t)!,
      menuTriggerSurface:
          Color.lerp(menuTriggerSurface, other.menuTriggerSurface, t)!,
      hoverSurface: Color.lerp(hoverSurface, other.hoverSurface, t)!,
      highlightSurface:
          Color.lerp(highlightSurface, other.highlightSurface, t)!,
      sheetHandle: Color.lerp(sheetHandle, other.sheetHandle, t)!,
      success: Color.lerp(success, other.success, t)!,
      destructive: Color.lerp(destructive, other.destructive, t)!,
      shadow: Color.lerp(shadow, other.shadow, t)!,
    );
  }
}

extension XylosThemeContext on BuildContext {
  ThemeData get appTheme => Theme.of(this);
  XylosTheme get xylosTheme => appTheme.extension<XylosTheme>()!;
}

extension XylosThemeData on ThemeData {
  XylosTheme get xylos => extension<XylosTheme>()!;

  BorderRadius get smallRadius =>
      BorderRadius.circular(kAppButtonRadius);

  RoundedRectangleBorder cardShape([Color? borderColor]) {
    return RoundedRectangleBorder(
      borderRadius: smallRadius,
      side: BorderSide(color: borderColor ?? xylos.moduleBorder),
    );
  }

  RoundedRectangleBorder tileShape() {
    return RoundedRectangleBorder(
      borderRadius: smallRadius,
    );
  }

  ShapeBorder get dialogShape => cardShape();

  ShapeBorder get bottomSheetShape {
    return const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(14)),
    );
  }

  ButtonStyle get primaryFilledButtonStyle => filledButtonTheme.style!;

  ButtonStyle get primaryTextButtonStyle => textButtonTheme.style!;

  ButtonStyle get largePrimaryFilledButtonStyle {
    return primaryFilledButtonStyle.copyWith(
      minimumSize: const WidgetStatePropertyAll(Size(0, 46)),
      padding: const WidgetStatePropertyAll(
        EdgeInsets.symmetric(horizontal: 22),
      ),
      textStyle: const WidgetStatePropertyAll(
        TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
      ),
    );
  }

  ButtonStyle get largePrimaryOutlinedButtonStyle {
    return OutlinedButton.styleFrom(
      foregroundColor: colorScheme.primary,
      minimumSize: const Size(0, 46),
      padding: const EdgeInsets.symmetric(horizontal: 22),
      textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
      side: BorderSide(color: colorScheme.primary),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(kAppButtonRadius),
      ),
    );
  }

  ButtonStyle get menuTriggerButtonStyle {
    return IconButton.styleFrom(
      foregroundColor: xylos.muted,
      backgroundColor: xylos.menuTriggerSurface,
      hoverColor: xylos.hoverSurface,
      highlightColor: xylos.highlightSurface,
      disabledBackgroundColor: xylos.menuTriggerSurface,
      minimumSize: const Size(34, 34),
      padding: EdgeInsets.zero,
      shape: tileShape(),
    );
  }

  ButtonStyle get desktopToolButtonStyle {
    return IconButton.styleFrom(
      foregroundColor: xylos.text,
      backgroundColor: xylos.menuSurface,
      disabledForegroundColor: xylos.muted.withOpacity(0.6),
      disabledBackgroundColor: xylos.menuSurface,
      hoverColor: xylos.hoverSurface,
      highlightColor: xylos.highlightSurface,
      minimumSize: const Size(38, 38),
      padding: EdgeInsets.zero,
      shape: cardShape(),
    );
  }

  ButtonStyle get mobileToolButtonStyle {
    return IconButton.styleFrom(
      foregroundColor: colorScheme.primary,
      backgroundColor: xylos.menuSurface,
      disabledForegroundColor: xylos.muted.withOpacity(0.55),
      disabledBackgroundColor: xylos.menuSurface,
      hoverColor: xylos.hoverSurface,
      highlightColor: xylos.highlightSurface,
      minimumSize: const Size(36, 36),
      padding: EdgeInsets.zero,
      shape: cardShape(),
    );
  }

  Color get listItemHoverColor => xylos.hoverSurface;

  Color get listItemSplashColor => xylos.highlightSurface;

  Color get subduedSurfaceColor => xylos.menuTriggerSurface;

  Color get subtleSurfaceColor => xylos.menuSurface;

  Color get mutedIconColor => xylos.muted;

  Color get primarySoftTextColor => colorScheme.primary;

  Color get primaryForegroundColor => colorScheme.onPrimary;

  Color get emphasizedShadowColor => xylos.shadow.withOpacity(0.16);

  ButtonStyle get subtleTextButtonStyle {
    return textButtonTheme.style!.copyWith(
      backgroundColor: WidgetStatePropertyAll(xylos.primarySoft),
      foregroundColor: WidgetStatePropertyAll(colorScheme.primary),
    );
  }

  InputDecoration desktopFieldDecoration({
    String? labelText,
    String? hintText,
  }) {
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(kAppButtonRadius),
      borderSide: BorderSide(color: xylos.moduleBorder),
    );
    return InputDecoration(
      labelText: labelText,
      hintText: hintText,
      isDense: true,
      filled: true,
      fillColor: xylos.menuSurface,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      border: border,
      enabledBorder: border,
      focusedBorder: border.copyWith(
        borderSide: BorderSide(color: colorScheme.primary),
      ),
    );
  }

  InputDecoration get mobileSearchDecoration {
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(kAppButtonRadius),
      borderSide: BorderSide(color: xylos.moduleBorder),
    );
    return InputDecoration(
      hintText: 'Search',
      hintStyle: TextStyle(color: xylos.muted, fontSize: 13),
      prefixIcon: Icon(Icons.search, size: 20, color: xylos.muted),
      filled: true,
      fillColor: xylos.menuSurface,
      border: border,
      enabledBorder: border,
      focusedBorder: border.copyWith(
        borderSide: BorderSide(color: colorScheme.primary),
      ),
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(vertical: 9),
    );
  }
}
