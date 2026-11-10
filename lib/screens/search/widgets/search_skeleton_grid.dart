import 'package:flutter/material.dart';

import '../../../widgets/cover_placeholder.dart';

/// 从 search_screen 抽出的零状态段：搜索加载骨架网格。
class SearchSkeletonGrid extends StatelessWidget {
  const SearchSkeletonGrid({super.key});

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 220,
        childAspectRatio: 0.60,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
      ),
      itemCount: 8,
      itemBuilder: (_, __) {
        // 骨架用已有的 CoverPlaceholder.shimmer（1500ms 渐变扫过），
        // 不再用静态灰块；布局、数量、尺寸与原来一致。
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              flex: 3,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: CoverPlaceholder.shimmer(),
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              flex: 2,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: SizedBox(
                        height: 12,
                        width: double.infinity,
                        child: CoverPlaceholder.shimmer(),
                      ),
                    ),
                    const SizedBox(height: 6),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(5),
                      child: SizedBox(
                        height: 10,
                        width: 80,
                        child: CoverPlaceholder.shimmer(),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
