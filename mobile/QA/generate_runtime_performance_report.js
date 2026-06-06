#!/usr/bin/env node
const fs = require('node:fs');
const path = require('node:path');

const MOBILE_DIR = process.argv[2] || path.join(process.cwd(), 'QA', 'runtime', 'runtime_report_latest.md');
const MIN_RUNTIME_SCORE = 95;
const TARGET_STARTUP_MS = 3000;
const TARGET_FPS_P95 = 57;
const TARGET_RESP_P99_MS = 180;

const runtimeReportPath = path.resolve(process.cwd(), MOBILE_DIR);
const runtimeDir = path.dirname(runtimeReportPath);
const reportDir = runtimeDir;
const tsMatch = path.basename(runtimeReportPath).match(/runtime_report_(\d{8}_\d{6})/);
const sampleTimestamp = tsMatch ? tsMatch[1] : '';

const toFiniteNumber = (value) => {
  const n = Number(value);
  return Number.isFinite(n) ? n : null;
};

const clampPercent = (value) => Math.max(0, Math.min(100, Math.round(value)));

const parseRuntimeReport = (content) => {
  const lines = content.split(/\r?\n/);
  const rows = [];
  for (const line of lines) {
    const row = line.match(/^\|\s*([^|]+?)\s*\|\s*([^|]+?)\s*\|\s*([^|]+?)\s*\|\s*([^|]+?)\s*\|\s*$/);
    if (!row) {
      continue;
    }

    const route = row[1].trim();
    if (route === '路由' || route === '---') {
      continue;
    }

    const durationSeconds = toFiniteNumber(row[2].trim());
    const status = row[3].trim();
    const note = row[4].trim();
    rows.push({
      route,
      durationSeconds,
      durationMs: durationSeconds !== null ? Math.round(durationSeconds * 1000) : null,
      status,
      note,
      safeRoute: route.replace(/\//g, '_') || 'root',
    });
  }
  return rows;
};

const findLatestByPrefix = (dir, regex, fallbackRouteMatch) => {
  if (!fs.existsSync(dir)) {
    return null;
  }

  const candidates = fs
    .readdirSync(dir)
    .filter((name) => regex.test(name))
    .map((name) => path.join(dir, name))
    .filter((candidate) => {
      if (fallbackRouteMatch && !fallbackRouteMatch.every((part) => part.length === 0)) {
        const base = path.basename(candidate);
        return fallbackRouteMatch.every((part) => base.includes(part));
      }
      return true;
    })
    .sort((a, b) => fs.statSync(b).mtimeMs - fs.statSync(a).mtimeMs);

  return candidates[0] || null;
};

const findTraceFile = (route) => {
  const safeRoute = route.safeRoute;
  if (sampleTimestamp) {
    const exact = findLatestByPrefix(runtimeDir, new RegExp(`^startup_${sampleTimestamp}_.*_${safeRoute}\\.json$`));
    if (exact) return exact;
  }
  return findLatestByPrefix(runtimeDir, new RegExp(`startup_.*_${safeRoute}\\.json$`));
};

const findLogFile = (route) => {
  const safeRoute = route.safeRoute;
  if (sampleTimestamp) {
    const exact = findLatestByPrefix(runtimeDir, new RegExp(`^run_${sampleTimestamp}_.*${safeRoute}\\.log$`));
    if (exact) return exact;
  }
  return findLatestByPrefix(runtimeDir, new RegExp(`run_.*${safeRoute}\\.log$`));
};

const findGfxFile = (route) => {
  const safeRoute = route.safeRoute;
  if (sampleTimestamp) {
    const exact = findLatestByPrefix(path.join(runtimeDir, 'gfxinfo'), new RegExp(`^${sampleTimestamp}.*${safeRoute}\\.txt$`));
    if (exact) return exact;
  }
  return findLatestByPrefix(path.join(runtimeDir, 'gfxinfo'), new RegExp(`.*${safeRoute}\\.txt$`));
};

const pickLastMatch = (content, patterns) => {
  for (const pattern of patterns) {
    const globalPattern = pattern.global ? pattern : new RegExp(pattern.source, `${pattern.flags}g`);
    const matches = Array.from(content.matchAll(globalPattern));
    if (!matches.length) {
      continue;
    }
    const last = matches[matches.length - 1];
    const num = toFiniteNumber(last[1]);
    if (num !== null) {
      return num;
    }
  }
  return null;
};

const analyzeLog = (filePath) => {
  const content = fs.readFileSync(filePath, 'utf8');
  const startupMs = pickLastMatch(content, [
    /app_time_stats: avg=([0-9.]+)ms/i,
    /first frame.*?([0-9.]+)\s*ms/i,
    /first_frame.*?([0-9.]+)\s*ms/i,
    /flutter run .*? took ([0-9]+)\s*ms/i,
    /firstInteractive.*?([0-9.]+)\s*ms/i,
  ]);

  const timelineProgress = Array.from(content.matchAll(/\[\s*\+([0-9]+)ms\]/g))
    .map((match) => Number(match[1]))
    .filter((value) => Number.isFinite(value));
  const maxTimelineMs = timelineProgress.length > 0 ? Math.max(...timelineProgress) : null;

  const crashHint = /error|exception|failed/i.test(content) ? 1 : 0;
  const hasFlutterRunExit = /exiting with code|exit code|ProcessException/i.test(content);
  const p99Match = content.match(/P99.*?([0-9]+)\s*ms/i);
  const p99Ms = p99Match ? toFiniteNumber(p99Match[1]) : null;
  const startupFromTimelineMs = maxTimelineMs && maxTimelineMs < 120000 ? maxTimelineMs : null;

  return {
    startupMs,
    p99Ms,
    startupFromTimelineMs,
    hasIssues: crashHint === 1,
    hasExit: hasFlutterRunExit,
    sampleBytes: content.length,
  };
};

const analyzeTrace = (filePath) => {
  try {
    const content = fs.readFileSync(filePath, 'utf8');
    if (!content.trim() || !content.trim().startsWith('{')) {
      return { file: filePath, parseable: false };
    }
  } catch {
    return { file: filePath, parseable: false };
  }

  try {
    const data = JSON.parse(fs.readFileSync(filePath, 'utf8'));
    const traceEvents = Array.isArray(data.traceEvents) ? data.traceEvents : [];
    const firstFrame = traceEvents.find((event) => String(event.name || '').toLowerCase().includes('firstframe'));
    const appStartup = traceEvents.find((event) => /first frame|first paint|frame start/i.test(String(event.name || '')));
    const frameTimes = traceEvents
      .filter((event) => event.name === 'Frame')
      .map((event) => {
        const dur = toFiniteNumber(event.dur);
        const ts = toFiniteNumber(event.ts);
        if (dur && ts) {
          return { dur, ts };
        }
        return null;
      })
      .filter(Boolean)
      .map((item) => item.dur);

    const firstFrameMs = firstFrame ? toFiniteNumber(firstFrame.ts) : null;
    const avgFrameMs = frameTimes.length > 0 ? Math.round(frameTimes.reduce((sum, dur) => sum + dur, 0) / frameTimes.length / 1000) : null;
    return {
      parseable: true,
      file: filePath,
      firstFrameMs,
      avgFrameMs,
      frameCount: frameTimes.length,
      appStartup: appStartup ? true : false,
    };
  } catch {
    return { file: filePath, parseable: false };
  }
};

const analyzeGfx = (filePath) => {
  const content = fs.readFileSync(filePath, 'utf8');
  const unavailable = /no process found|failed while dumping app/i.test(content);
  const p95Match = content.match(/95th percentile:\s*([0-9.]+)\s*ms/i);
  const p95GpuMatch = content.match(/95th gpu percentile:\s*([0-9.]+)\s*ms/i);
  const p95FrameMs = p95Match
    ? toFiniteNumber(p95Match[1])
    : (p95GpuMatch ? toFiniteNumber(p95GpuMatch[1]) : null);
  const fps = p95FrameMs && p95FrameMs > 0 ? 1000 / p95FrameMs : null;
  const jank = pickLastMatch(content, [
    /janky frames:\s*([0-9]+)/i,
    /jank:\s*([0-9]+)/i,
    /missed\s*frames:\s*([0-9]+)/i,
  ]);
  const totalFrames = pickLastMatch(content, [
    /total frames rendered:\s*([0-9]+)/i,
  ]);

  return {
    file: filePath,
    unavailable,
    fps,
    jankFrames: jank,
    totalFrames,
  };
};

const scoreByStartupMs = (ms) => {
  if (ms === null) return 50;
  if (ms <= TARGET_STARTUP_MS) return 100;
  if (ms <= 5000) return 85;
  if (ms <= 8000) return 60;
  if (ms <= 12000) return 35;
  return 10;
};

const scoreByFps = (fps) => {
  if (fps === null) return 45;
  if (fps >= TARGET_FPS_P95 * 1.2) return 100;
  if (fps >= TARGET_FPS_P95) return 90;
  if (fps >= 45) return 60;
  if (fps >= 30) return 30;
  return 10;
};

const scoreByInteraction = (ms) => {
  if (ms === null) return 45;
  if (ms <= TARGET_RESP_P99_MS) return 100;
  if (ms <= 220) return 85;
  if (ms <= 300) return 55;
  if (ms <= 500) return 35;
  return 10;
};

const scoreByJank = (jank, frames) => {
  if (jank === null || frames === null || frames <= 0) {
    return 45;
  }
  const ratio = jank / frames;
  if (ratio <= 0.01) return 100;
  if (ratio <= 0.03) return 80;
  if (ratio <= 0.08) return 50;
  if (ratio <= 0.15) return 30;
  return 10;
};

const toPercent = (value) => {
  const n = toFiniteNumber(value);
  if (n === null) return '';
  return `${n.toFixed(2)}%`;
};

let reportContent = '';
try {
  reportContent = fs.readFileSync(runtimeReportPath, 'utf8');
} catch {
  console.error(`[错误] 读取运行时报告失败: ${runtimeReportPath}`);
  process.exit(2);
}

const routes = parseRuntimeReport(reportContent);
if (routes.length === 0) {
  console.error('[错误] 未从运行时报告解析到路由明细。');
  process.exit(2);
}

const rows = [];
for (const route of routes) {
  const logFile = findLogFile(route);
  const gfxFile = findGfxFile(route);
  const traceFile = findTraceFile(route);

  let logStats = null;
  if (logFile) {
    logStats = analyzeLog(logFile);
  }

  const traceStats = traceFile ? analyzeTrace(traceFile) : { parseable: false, file: null };
  const gfxStats = gfxFile ? analyzeGfx(gfxFile) : { file: null };
  const startupMs = logStats?.startupMs ?? route.durationMs ?? null;
  const effectiveStartupMs = startupMs ?? (logStats?.startupFromTimelineMs ?? null);
  const p99Ms = logStats?.p99Ms ?? null;
  const fps = gfxStats.fps ?? null;
  const jankFrames = gfxStats.jankFrames ?? null;
  const totalFrames = gfxStats.totalFrames ?? null;

  const startupScore = route.status === 'PASS' ? scoreByStartupMs(effectiveStartupMs) : 0;
  const fpsScore = route.status === 'PASS' ? scoreByFps(fps) : 0;
  const interactionScore = route.status === 'PASS' ? scoreByInteraction(p99Ms) : 0;
  const jankScore = route.status === 'PASS' ? scoreByJank(jankFrames, totalFrames) : 0;
  const runtimeScore = clampPercent(startupScore * 0.5 + fpsScore * 0.3 + interactionScore * 0.2);
  const readinessScore = clampPercent(runtimeScore * 0.7 + jankScore * 0.3);

  rows.push({
    route: route.route,
    status: route.status,
    durationSeconds: route.durationSeconds,
    note: route.note,
    startupMs: effectiveStartupMs,
    p99Ms,
    fpsP95: fps,
    jankFrames,
    totalFrames,
    logFile: logFile ? path.relative(process.cwd(), logFile) : '',
    gfxFile: gfxFile ? path.relative(process.cwd(), gfxFile) : '',
    traceFile: traceFile ? path.relative(process.cwd(), traceFile) : '',
    traceParseable: traceStats.parseable,
    score: {
      startup: startupScore,
      fps: fpsScore,
      interactionP99: interactionScore,
      jank: jankScore,
      runtime: runtimeScore,
      readiness: readinessScore,
    },
    risk: !gfxStats.unavailable,
  });
}

rows.sort((a, b) => a.route.localeCompare(b.route));
const totalRoutes = rows.length;
const failRoutes = rows.filter((row) => row.status !== 'PASS');
const passRoutes = rows.filter((row) => row.status === 'PASS');
const avgRuntime = Math.round(rows.reduce((sum, row) => sum + row.score.runtime, 0) / totalRoutes);
const avgReadiness = Math.round(rows.reduce((sum, row) => sum + row.score.readiness, 0) / totalRoutes);
const minRuntime = Math.min(...rows.map((row) => row.score.runtime));
const minReadiness = Math.min(...rows.map((row) => row.score.readiness));
const allGood = rows.every((row) => row.score.runtime >= MIN_RUNTIME_SCORE);
const hasNoApp = rows.some((row) => row.gfxFile === '' || row.traceFile === '' || row.logFile === '');

const reportTs = new Date().toISOString().replace('T', ' ').slice(0, 19);
const outputDir = reportDir;
const timestamp = sampleTimestamp || new Date().toISOString().replace(/[-:]/g, '').slice(0, 15).replace('T', '_');
const mdPath = path.join(outputDir, `runtime_performance_${timestamp}.md`);
const jsonPath = path.join(outputDir, `runtime_performance_${timestamp}.json`);
const latestMdPath = path.join(runtimeDir, 'runtime_performance_latest.md');
const latestJsonPath = path.join(runtimeDir, 'runtime_performance_latest.json');

const lines = [];
lines.push('# Android 运行时性能报告');
lines.push(`- 生成时间: ${reportTs}`);
lines.push(`- 采样报告: ${path.relative(process.cwd(), runtimeReportPath)}`);
lines.push(`- 路由样本: ${totalRoutes}`);
lines.push('');
lines.push('| 路由 | 状态 | 耗时(s) | 首帧推断(ms) | 95th FPS | 交互P99(ms) | 掉帧 | 路由得分 |');
lines.push('| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: |');
for (const row of rows) {
  const fpsLabel = row.fpsP95 === null ? '-' : row.fpsP95.toFixed(2);
  const p99Label = row.p99Ms === null ? '-' : `${row.p99Ms.toFixed(2)}ms`;
  const startupLabel = row.startupMs === null ? '-' : `${row.startupMs.toFixed(2)}ms`;
  const jankLabel = row.jankFrames === null ? '-' : `${row.jankFrames}/${row.totalFrames ?? '?'}`;
  lines.push(
    `| ${row.route} | ${row.status} | ${row.durationSeconds ?? '-'} | ${startupLabel} | ${fpsLabel} | ${p99Label} | ${jankLabel} | ${row.score.runtime} |`,
  );
}
lines.push('');
lines.push('## 聚合');
lines.push(`- PASS 路由: ${passRoutes.length}/${totalRoutes}`);
lines.push(`- FAIL/异常: ${failRoutes.length}/${totalRoutes}`);
lines.push(`- 平均运行分: ${avgRuntime}`);
lines.push(`- 平均可交互分: ${avgReadiness}`);
lines.push(`- 最低运行分: ${minRuntime}`);
lines.push(`- 最低可交互分: ${minReadiness}`);
lines.push(`- 是否全站达标(>=${MIN_RUNTIME_SCORE}): ${allGood ? '是' : '否'}`);
if (hasNoApp) {
  lines.push('- 说明: 部分路由未回传 log/gfx/trace，评分中包含缺失惩罚。');
}
lines.push('- 风险提示: 评分更侧重「可复测时长」与「启动闭环」可得性；如需 95 FPS 指标需补充稳定的 `dumpsys gfxinfo` 帧数据。');

const payload = {
  generatedAt: new Date().toISOString(),
  runtimeReport: path.relative(process.cwd(), runtimeReportPath),
  sampleTimestamp: sampleTimestamp || 'unknown',
  summary: {
    totalRoutes,
    passRoutes: passRoutes.length,
    failRoutes: failRoutes.length,
    avgRuntimeScore: avgRuntime,
    avgReadinessScore: avgReadiness,
    minRuntimeScore: minRuntime,
    minReadinessScore: minReadiness,
    allPassTarget95: allGood,
    hasMissingArtifacts: hasNoApp,
    risk: {
      targetStartupMs: TARGET_STARTUP_MS,
      targetFpsP95: TARGET_FPS_P95,
      targetInteractionMs: TARGET_RESP_P99_MS,
    },
  },
  routes: rows,
};

fs.writeFileSync(mdPath, `${lines.join('\n')}\n`);
fs.writeFileSync(jsonPath, `${JSON.stringify(payload, null, 2)}\n`);
fs.writeFileSync(latestMdPath, fs.readFileSync(mdPath));
fs.writeFileSync(latestJsonPath, fs.readFileSync(jsonPath));

console.log(`runtime performance report: ${path.relative(process.cwd(), mdPath)}`);
console.log(`json: ${path.relative(process.cwd(), jsonPath)}`);
if (!allGood) {
  console.log(`[提醒] 当前运行时指标未全部达标 95+（最低运行分=${minRuntime}）。`);
  process.exitCode = 1;
}
