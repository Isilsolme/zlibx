import 'package:flutter/material.dart';

/// 评论区共享的圆形头像：有图显示图，无图或加载失败显示人形图标，
/// 可点击跳主页。
///
/// 用 [Image.errorBuilder] 做失败回退，比 CircleAvatar 的
/// onBackgroundImageError（child 为空时行为不定）更可靠。
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
    final Widget avatar;
    if (avatarUrl.isEmpty) {
      avatar = CircleAvatar(
        radius: radius,
        backgroundColor: cs.primaryContainer,
        child: Icon(
          Icons.person_rounded,
          color: cs.onPrimaryContainer,
          size: radius * 1.1,
        ),
      );
    } else {
      avatar = ClipOval(
        child: SizedBox(
          width: radius * 2,
          height: radius * 2,
          child: Image(
            image: NetworkImage(avatarUrl),
            fit: BoxFit.cover,
            // 加载中先铺底色，避免出现刺眼的透明/黑块。
            frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
              if (wasSynchronouslyLoaded) return child;
              return ColoredBox(color: cs.primaryContainer, child: child);
            },
            errorBuilder: (_, __, ___) => Container(
              color: cs.primaryContainer,
              alignment: Alignment.center,
              child: Icon(
                Icons.person_rounded,
                color: cs.onPrimaryContainer,
                size: radius * 1.1,
              ),
            ),
          ),
        ),
      );
    }
    if (onTap == null) return avatar;
    return InkWell(
      onTap: onTap,
      customBorder: const CircleBorder(),
      child: avatar,
    );
  }
}
