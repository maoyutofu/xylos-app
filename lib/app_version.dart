class AppVersion {
  const AppVersion._();

  static const String version = String.fromEnvironment(
    'APP_VERSION',
    defaultValue: 'dev',
  );

  static const String buildNumber = String.fromEnvironment(
    'APP_BUILD_NUMBER',
    defaultValue: '0',
  );

  static String get displayVersion {
    if (buildNumber.isEmpty || buildNumber == '0') {
      return version;
    }
    return '$version+$buildNumber';
  }
}
