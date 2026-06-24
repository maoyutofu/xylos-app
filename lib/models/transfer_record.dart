import 'dart:convert';

enum TransferDirection {
  upload,
  download;

  static TransferDirection fromName(String value) {
    return TransferDirection.values.firstWhere(
      (item) => item.name == value,
      orElse: () => TransferDirection.download,
    );
  }
}

enum TransferStatus {
  running,
  success,
  failed;

  static TransferStatus fromName(String value) {
    return TransferStatus.values.firstWhere(
      (item) => item.name == value,
      orElse: () => TransferStatus.failed,
    );
  }
}

class TransferRecord {
  const TransferRecord({
    required this.id,
    required this.serverName,
    required this.remotePath,
    required this.localPath,
    required this.direction,
    required this.status,
    required this.createdAt,
    this.finishedAt,
    this.errorMessage,
  });

  final String id;
  final String serverName;
  final String remotePath;
  final String localPath;
  final TransferDirection direction;
  final TransferStatus status;
  final DateTime createdAt;
  final DateTime? finishedAt;
  final String? errorMessage;

  TransferRecord copyWith({
    String? id,
    String? serverName,
    String? remotePath,
    String? localPath,
    TransferDirection? direction,
    TransferStatus? status,
    DateTime? createdAt,
    DateTime? finishedAt,
    String? errorMessage,
    bool clearFinishedAt = false,
    bool clearErrorMessage = false,
  }) {
    return TransferRecord(
      id: id ?? this.id,
      serverName: serverName ?? this.serverName,
      remotePath: remotePath ?? this.remotePath,
      localPath: localPath ?? this.localPath,
      direction: direction ?? this.direction,
      status: status ?? this.status,
      createdAt: createdAt ?? this.createdAt,
      finishedAt: clearFinishedAt ? null : (finishedAt ?? this.finishedAt),
      errorMessage:
          clearErrorMessage ? null : (errorMessage ?? this.errorMessage),
    );
  }

  Map<String, Object?> toJson() {
    return {
      'id': id,
      'serverName': serverName,
      'remotePath': remotePath,
      'localPath': localPath,
      'direction': direction.name,
      'status': status.name,
      'createdAt': createdAt.toIso8601String(),
      'finishedAt': finishedAt?.toIso8601String(),
      'errorMessage': errorMessage,
    };
  }

  factory TransferRecord.fromJson(Map<String, Object?> json) {
    return TransferRecord(
      id: json['id'] as String? ?? '',
      serverName: json['serverName'] as String? ?? '',
      remotePath: json['remotePath'] as String? ?? '',
      localPath: json['localPath'] as String? ?? '',
      direction: TransferDirection.fromName(
        json['direction'] as String? ?? '',
      ),
      status: TransferStatus.fromName(json['status'] as String? ?? ''),
      createdAt: DateTime.tryParse(json['createdAt'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
      finishedAt: DateTime.tryParse(json['finishedAt'] as String? ?? ''),
      errorMessage: json['errorMessage'] as String?,
    );
  }

  String encode() => jsonEncode(toJson());

  static TransferRecord decode(String value) {
    return TransferRecord.fromJson(jsonDecode(value) as Map<String, Object?>);
  }
}
