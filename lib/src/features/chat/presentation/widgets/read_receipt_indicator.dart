import 'package:flutter/material.dart';

import '../../../../core/models/peer_identity.dart';
import '../../../../core/widgets/profile_avatar.dart';
import '../../domain/entities/read_receipt.dart';

/// Displays a row of tiny profile avatars indicating which users have
/// seen a particular message. Mimics Messenger-style read receipts.
///
/// If there are more readers than [maxAvatars], a "+N" overflow indicator
/// is shown.
class ReadReceiptIndicator extends StatelessWidget {
  const ReadReceiptIndicator({
    super.key,
    required this.receipts,
    this.localUserId,
    this.maxAvatars = 5,
    this.avatarSize = 16.0,
    this.alignment = MainAxisAlignment.end,
  });

  /// The read receipts for a single message.
  final List<ReadReceipt> receipts;

  /// The local user's ID. Receipts from the local user are excluded from
  /// display (you don't need to see your own "seen" indicator).
  final String? localUserId;

  /// Maximum number of avatars to show before showing "+N".
  final int maxAvatars;

  /// Size of each avatar circle.
  final double avatarSize;

  /// How to align the row of avatars (default: end-aligned for sent msgs).
  final MainAxisAlignment alignment;

  @override
  Widget build(BuildContext context) {
    // Filter out the local user's own receipts.
    final visibleReceipts = localUserId != null
        ? receipts.where((r) => r.seenByUserId != localUserId).toList()
        : receipts;

    if (visibleReceipts.isEmpty) {
      return const SizedBox.shrink();
    }

    final displayed = visibleReceipts.length > maxAvatars
        ? visibleReceipts.sublist(0, maxAvatars)
        : visibleReceipts;
    final overflow = visibleReceipts.length - displayed.length;

    return Padding(
      padding: const EdgeInsets.only(top: 4.0),
      child: Row(
        mainAxisAlignment: alignment,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Slightly overlapping avatars for a compact look.
          ...List.generate(displayed.length, (index) {
            final receipt = displayed[index];
            final identity = PeerIdentity(
              id: receipt.seenByUserId,
              displayName: receipt.seenByDisplayName,
              profileImage: receipt.seenByProfileImage,
            );
            return Padding(
              padding: EdgeInsets.only(left: index == 0 ? 0 : 2.0),
              child: Tooltip(
                message: 'Seen by ${receipt.seenByDisplayName}',
                child: ProfileAvatar(identity: identity, size: avatarSize),
              ),
            );
          }),
          if (overflow > 0)
            Padding(
              padding: const EdgeInsets.only(left: 4.0),
              child: Text(
                '+$overflow',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  fontSize: avatarSize * 0.65,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
