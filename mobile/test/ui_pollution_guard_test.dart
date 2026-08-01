import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('mobile UI does not reintroduce noisy copy or heavy effects', () {
    final libDir = _existingDirectory(['mobile/lib', 'lib']);
    final files = libDir
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => file.path.endsWith('.dart'))
        .where(_isVisibleUiFile);

    final violations = <String>[];
    for (final file in files) {
      final content = file.readAsStringSync();
      for (final forbidden in _forbiddenUiFragments) {
        if (content.contains(forbidden)) {
          violations.add('${file.path}: $forbidden');
        }
      }
    }

    expect(violations, isEmpty, reason: violations.join('\n'));
  });

  test('mobile tests do not enforce no-op motion wrappers', () {
    final testDir = _existingDirectory(['mobile/test', 'test']);
    final files = testDir
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => file.path.endsWith('.dart'))
        .where((file) => !file.path.endsWith('ui_pollution_guard_test.dart'));

    final violations = <String>[];
    for (final file in files) {
      final content = file.readAsStringSync();
      for (final forbidden in _forbiddenTestFragments) {
        if (content.contains(forbidden)) {
          violations.add('${file.path}: $forbidden');
        }
      }
    }

    expect(violations, isEmpty, reason: violations.join('\n'));
  });
}

Directory _existingDirectory(List<String> paths) {
  for (final path in paths) {
    final directory = Directory(path);
    if (directory.existsSync()) {
      return directory;
    }
  }
  throw StateError('Cannot find mobile lib directory');
}

bool _isVisibleUiFile(File file) {
  final path = file.path.replaceAll(r'\', '/');
  return path.contains('/presentation/') ||
      path.contains('/app/widgets/') ||
      path.contains('/features/main/');
}

const _forbiddenUiFragments = [
  '快速记一笔',
  '功能中心',
  '账本管理、计划提醒、智能数据和安全设置',
  '访问令牌',
  '连接服务器',
  '连接码已生成',
  '一次性连接码',
  '复制连接码',
  '未连接 ·',
  '长期可用',
  '服务器备份',
  '完整副本',
  '完整备份',
  '定期副本',
  '保留份数',
  '交易 CSV',
  '下载备份',
  '导出 CSV',
  '测试发送',
  '测试成功',
  '检查发送',
  '发送检查通过',
  '发送检查失败',
  '检查中',
  '发送地址',
  '通道地址',
  '连接端口',
  '邮箱服务',
  '安全密钥',
  '头像地址',
  '访问凭证',
  '按条件保存',
  '全部类型',
  '全部账户',
  '余额不为零或已有交易记录的账户无法删除，可选择归档。',
  '有余额或交易时请先归档。',
  '请先归档后再删除。',
  '账户余额会自动调整',
  '余额将同步调整',
  '关联记录不变。',
  '清除本机登录态并重新连接。',
  '本机登录态',
  '关闭后直接进入登录页。',
  '用所选副本覆盖当前数据。',
  '当前数据将被覆盖。',
  '已生成报告保留。',
  '历史报告保留。',
  '报告将移除。',
  '预算记录将移除。',
  '该设备将无法使用。',
  '登录页将直接显示。',
  '关联交易不变。',
  '已记交易不变。',
  '账户流水',
  '相关交易将取消分类。',
  '历史交易保留。',
  '历史归属保留。',
  '已有交易保留。',
  '这台设备将停止访问账本。',
  '停止跟踪',
  '仅删除报告。',
  '仅删除提醒记录。',
  '提醒记录将移除。',
  '仅删除借贷记录。',
  '借贷记录将移除。',
  '账本交易会保留',
  '相关交易转为未分类。',
  '暂无数据',
  '暂无可用方式',
  '暂无报告',
  '暂无内容',
  '暂无快捷模板',
  '暂无个人资料',
  '暂无授权',
  '暂无设备',
  '还没有授权设备',
  '暂无家庭成员支出',
  '暂无负债提醒',
  '暂无还款账户',
  '暂无借出记录',
  '暂无借入记录',
  '暂无已结清记录',
  '暂无还款记录',
  '暂无标签',
  '暂无支出分类',
  '暂无收入分类',
  '本月暂无趋势数据',
  '本月暂无分类数据',
  '暂无月度数据',
  '暂无支出数据',
  '暂无收入数据',
  '暂无交易明细',
  '暂无流水记录',
  '没有匹配的交易',
  '旧附件清理失败',
  '控制台',
  '中枢',
  '矩阵',
  '雷达',
  'Hub',
  '预留',
  '证据',
  '部署拓扑',
  '连接证据',
  'AI 输入',
  '数据保险库',
  '安全态势',
  '预算风险',
  "title: '风险'",
  '家庭协同',
  '标签库',
  '分类库',
  '流水审计',
  '失败：',
  r'$error',
  'HapticFeedback',
  'AnimatedContainer',
  'TweenAnimationBuilder',
  'BackdropFilter',
  'ImageFilter',
  'StaggeredEntrance',
  'staggered_entrance',
];

const _forbiddenTestFragments = [
  'StaggeredEntrance',
  'staggered_entrance',
  '分段入场动效',
  '入场动效',
];
