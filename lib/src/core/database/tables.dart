import 'package:drift/drift.dart';

/// Table for storing chat rooms.
@DataClassName('ChatRoomEntry')
class ChatRooms extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get description => text().withDefault(const Constant(''))();
  TextColumn get ownerId => text()();
  BoolColumn get isPrivate => boolean().withDefault(const Constant(false))();
  TextColumn get passwordHash => text().nullable()();
  TextColumn get memberIds => text().withDefault(const Constant('[]'))();
  IntColumn get maxMembers => integer().nullable()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// Table for storing conversations (legacy, for migration compatibility).
@DataClassName('ConversationEntry')
class Conversations extends Table {
  TextColumn get id => text()();
  TextColumn get title => text()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// Table for storing chat messages.
@DataClassName('ChatMessageEntry')
class ChatMessages extends Table {
  TextColumn get id => text()();
  TextColumn get conversationId => text().references(Conversations, #id)();
  TextColumn get senderId => text()();
  TextColumn get sender => text()();
  TextColumn get content => text()();
  DateTimeColumn get sentAt => dateTime()();
  TextColumn get attachments => text().withDefault(const Constant('[]'))();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// Table for sync metadata.
@DataClassName('SyncMetadataEntry')
class SyncMetadata extends Table {
  TextColumn get entityId => text()();
  TextColumn get entityType => text()(); // 'room', 'conversation', 'message'
  DateTimeColumn get lastModified => dateTime()();
  IntColumn get version => integer().withDefault(const Constant(1))();

  @override
  Set<Column<Object>> get primaryKey => {entityId, entityType};
}
