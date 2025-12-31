class ChatAttachment {
  const ChatAttachment({
    required this.id,
    required this.filename,
    required this.mimeType,
    required this.sizeBytes,
    required this.uri,
  });

  final String id;
  final String filename;
  final String mimeType;
  final int sizeBytes;
  final String uri;

  ChatAttachment copyWith({
    String? id,
    String? filename,
    String? mimeType,
    int? sizeBytes,
    String? uri,
  }) {
    return ChatAttachment(
      id: id ?? this.id,
      filename: filename ?? this.filename,
      mimeType: mimeType ?? this.mimeType,
      sizeBytes: sizeBytes ?? this.sizeBytes,
      uri: uri ?? this.uri,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'filename': filename,
    'mimeType': mimeType,
    'sizeBytes': sizeBytes,
    'uri': uri,
  };

  factory ChatAttachment.fromJson(Map<String, dynamic> json) {
    return ChatAttachment(
      id: json['id'] as String,
      filename: json['filename'] as String,
      mimeType: json['mimeType'] as String,
      sizeBytes: (json['sizeBytes'] as num).toInt(),
      uri: json['uri'] as String,
    );
  }
}
