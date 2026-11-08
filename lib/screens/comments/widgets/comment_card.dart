import 'package:flutter/material.dart';
import 'package:olib_api_plugin/olib_api_plugin.dart';
import 'comment_avatar.dart';
import 'comment_metric_chip.dart';

/// 单条评论。回复（`parentId` 非空）带左侧竖线，与父评论视觉上成组。
class CommentCard extends StatelessWidget {
  final BookComment comment;
  final int replyCount;
  final bool likePending;
  final VoidCallback onLike;
  final VoidCallback onReply;
  final VoidCallback onAvatarTap;

  const CommentCard({
    super.key,
    required this.comment,
    required this.replyCount,
    required this.likePending,
    required this.onLike,
    required this.onReply,
    required this.onAvatarTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final date = comment.dateRelative.isNotEmpty
        ? comment.dateRelative
        : comment.date;
    final isReply = comment.parentId != null;

    final body = Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CommentAvatar(avatarUrl: comment.userAvatar, onTap: onAvatarTap),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Flexible(
                    child: Text(
                      comment.userName,
                      style: tt.bodyMedium
                          ?.copyWith(fontWeight: FontWeight.w600),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (date.isNotEmpty) ...[
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                      child: Icon(
                        Icons.circle,
                        size: 3,
                        color: cs.outline,
                      ),
                    ),
                    Flexible(
                      child: Text(
                        date,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: tt.bodySmall?.copyWith(
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 4),
              SelectableText(
                comment.text,
                style: tt.bodyMedium?.copyWith(height: 1.45),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  const Spacer(),
                  CommentMetricChip(
                    icon: Icons.chat_bubble_outline_rounded,
                    count: replyCount,
                    onTap: onReply,
                  ),
                  const SizedBox(width: 4),
                  CommentMetricChip(
                    icon: comment.isLiked
                        ? Icons.thumb_up_rounded
                        : Icons.thumb_up_outlined,
                    count: comment.likeCount,
                    active: comment.isLiked,
                    busy: likePending,
                    onTap: onLike,
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );

    if (!isReply) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
        child: body,
      );
    }
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 2, 16, 2),
      padding: const EdgeInsets.only(left: 12),
      decoration: BoxDecoration(
        border: Border(
          left: BorderSide(color: cs.outlineVariant, width: 2),
        ),
      ),
      child: body,
    );
  }
}
