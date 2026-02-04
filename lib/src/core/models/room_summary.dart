class RoomSummary {
  const RoomSummary({
    required this.roomTitle,
    required this.hostName,
    this.description,
  });

  final String roomTitle;
  final String hostName;
  final String? description;

  @override
  String toString() => '$roomTitle · $hostName';
}
