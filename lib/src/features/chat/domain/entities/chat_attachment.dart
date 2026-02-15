class ChatAttachment {
  const ChatAttachment({
    required this.id,
    required this.filename,
    required this.mimeType,
    required this.sizeBytes,
    required this.uri,
    this.senderHostIp,
    this.senderPort,
  });

  final String id;
  final String filename;
  final String mimeType;
  final int sizeBytes;
  final String uri;

  /// IP address of sender for P2P file download (optional)
  final String? senderHostIp;

  /// Port of sender for P2P file download (optional)
  final int? senderPort;

  ChatAttachment copyWith({
    String? id,
    String? filename,
    String? mimeType,
    int? sizeBytes,
    String? uri,
    String? senderHostIp,
    int? senderPort,
  }) {
    return ChatAttachment(
      id: id ?? this.id,
      filename: filename ?? this.filename,
      mimeType: mimeType ?? this.mimeType,
      sizeBytes: sizeBytes ?? this.sizeBytes,
      uri: uri ?? this.uri,
      senderHostIp: senderHostIp ?? this.senderHostIp,
      senderPort: senderPort ?? this.senderPort,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'filename': filename,
    'mimeType': mimeType,
    'sizeBytes': sizeBytes,
    'uri': uri,
    if (senderHostIp != null) 'senderHostIp': senderHostIp,
    if (senderPort != null) 'senderPort': senderPort,
  };

  factory ChatAttachment.fromJson(Map<String, dynamic> json) {
    return ChatAttachment(
      id: json['id'] as String,
      filename: json['filename'] as String,
      mimeType: json['mimeType'] as String,
      sizeBytes: (json['sizeBytes'] as num).toInt(),
      uri: json['uri'] as String? ?? '',
      senderHostIp: json['senderHostIp'] as String?,
      senderPort: json['senderPort'] as int?,
    );
  }
}
