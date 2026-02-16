import 'dart:convert';

import 'peer_identity.dart';

/// Represents a pending join request from a peer wanting to enter a
/// private conversation that requires host approval.
class JoinRequest {
  const JoinRequest({
    required this.peerId,
    required this.transportClientId,
    required this.displayName,
    this.fullName,
    this.profileImage,
    this.groupName,
    this.role,
    required this.requestedAt,
  });

  /// The peer's identity ID (from [PeerIdentity.id]).
  final String peerId;

  /// The transport-level client ID used for sending targeted messages.
  final String transportClientId;

  final String displayName;
  final String? fullName;
  final String? profileImage;
  final String? groupName;
  final String? role;
  final DateTime requestedAt;

  /// Build a [PeerIdentity] from this request so it can be passed to
  /// [ProfileAvatar] and similar widgets.
  PeerIdentity toPeerIdentity() {
    return PeerIdentity(
      id: peerId,
      displayName: displayName,
      name: fullName,
      profileImage: profileImage,
      groupName: groupName,
      role: UserRole.values.firstWhere(
        (e) => e.name == role,
        orElse: () => UserRole.other,
      ),
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'peerId': peerId,
      'displayName': displayName,
      if (fullName != null) 'fullName': fullName,
      if (profileImage != null) 'profileImage': profileImage,
      if (groupName != null) 'groupName': groupName,
      if (role != null) 'role': role,
      'requestedAt': requestedAt.toUtc().toIso8601String(),
    };
  }

  String encode() => jsonEncode(toJson());

  static JoinRequest? tryParse(
    String jsonStr, {
    required String transportClientId,
  }) {
    try {
      final decoded = jsonDecode(jsonStr);
      if (decoded is! Map<String, dynamic>) return null;
      final peerId = decoded['peerId'];
      final displayName = decoded['displayName'];
      if (peerId is! String || displayName is! String) return null;
      return JoinRequest(
        peerId: peerId,
        transportClientId: transportClientId,
        displayName: displayName,
        fullName: decoded['fullName'] as String?,
        profileImage: decoded['profileImage'] as String?,
        groupName: decoded['groupName'] as String?,
        role: decoded['role'] as String?,
        requestedAt:
            DateTime.tryParse(decoded['requestedAt'] as String? ?? '') ??
            DateTime.now().toUtc(),
      );
    } catch (_) {
      return null;
    }
  }
}

/// The approval status a **client** tracks while waiting for the host
/// to confirm or deny a join request.
enum JoinApprovalStatus {
  /// Request has been sent, waiting for host response.
  pending,

  /// Host approved the join request.
  approved,

  /// Host denied the join request.
  denied,
}
