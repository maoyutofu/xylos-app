class WebDavResource {
  const WebDavResource({
    required this.path,
    required this.name,
    required this.isDirectory,
    required this.size,
    required this.etag,
    required this.contentType,
    required this.lastModified,
  });

  final String path;
  final String name;
  final bool isDirectory;
  final int? size;
  final String? etag;
  final String? contentType;
  final DateTime? lastModified;
}
