bool isProtectedRepositoryPath(String path) {
  final normalized = path
      .replaceAll('\\', '/')
      .toLowerCase()
      .trim();
  if (normalized.isEmpty) return false;

  final segments = normalized.split('/');
  final name = segments.isEmpty ? normalized : segments.last;

  if (name == '.env' || name.startsWith('.env.')) return true;

  const blockedNames = <String>{
    'local.properties',
    'key.properties',
    'credentials.json',
    'secrets.json',
    'service-account.json',
    'service_account.json',
  };
  if (blockedNames.contains(name)) return true;

  const blockedExtensions = <String>{
    '.pem',
    '.key',
    '.p12',
    '.pfx',
    '.jks',
    '.keystore',
  };
  if (blockedExtensions.any(name.endsWith)) return true;

  return segments.any(
    (segment) =>
        segment == 'secrets' ||
        segment == '.secrets' ||
        segment == 'credentials',
  );
}
