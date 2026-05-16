import 'package:flutter/material.dart';

import '../../../app/widgets/adaptive_page_container.dart';
import '../../../app/widgets/app_state_views.dart';

class MobileStatisticsPage extends StatelessWidget {
  const MobileStatisticsPage({super.key});

  /// 构建统计页占位结构。
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('统计')),
      body: const AdaptivePageContainer(
        child: AppEmptyView(
          title: '暂无统计数据',
          message: '完成记账后，这里会展示收支趋势和分类占比。',
          icon: Icons.bar_chart_outlined,
        ),
      ),
    );
  }
}
