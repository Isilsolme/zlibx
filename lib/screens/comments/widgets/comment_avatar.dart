import 'package:flutter/material.dart';

/// 评论区共享的圆形头像：有图显示图，无图显示人形图标，可点击跳主页。
class CommentAvatar extends StatelessWidget {
  final String avatarUrl;
  final double radius;
  final VoidCallback? onTap;

  const CommentAvatar({
    super.key,
    required this.avatarUrl,
    this.radius = 20,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final avatar = CircleAvatar(
      radius: radius,
      backgroundColor: cs.primaryContainer,
      backgroundImage:
          avatarUrl.isNotEmpty ? NetworkImage(avatarUrl) : null,
      child: avatarUrl.isEmpty
          ? Icon(
              Icons.person_rounded,
              color: cs.onPrimaryContainer,
              size: radius * 1.1,
            )
          : null,
    );
    if (onTap == null) return avatar;
    return InkWell(
      onTap: onTap,
      customBorder: const CircleBorder(),
      child: avatar,
    );
  }
}
