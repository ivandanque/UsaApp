class Conversation {
  const Conversation({
    required this.id,
    required this.title,
    this.isPrivate = false,
    this.passwordHash,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String title;
  final bool isPrivate;
  final String? passwordHash;
  final DateTime createdAt;
  final DateTime updatedAt;

  Conversation copyWith({
    String? id,
    String? title,
    bool? isPrivate,
    String? passwordHash,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return Conversation(
      id: id ?? this.id,
      title: title ?? this.title,
      isPrivate: isPrivate ?? this.isPrivate,
      passwordHash: passwordHash ?? this.passwordHash,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'id': id,
      'title': title,
      'isPrivate': isPrivate,
      if (passwordHash != null) 'passwordHash': passwordHash,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
    };
  }

  factory Conversation.fromJson(Map<String, dynamic> json) {
    return Conversation(
      id: json['id'] as String,
      title: json['title'] as String,
      isPrivate: json['isPrivate'] as bool? ?? false,
      passwordHash: json['passwordHash'] as String?,
      createdAt: DateTime.parse(json['createdAt'] as String),
      updatedAt: DateTime.parse(json['updatedAt'] as String),
    );
  }
}
