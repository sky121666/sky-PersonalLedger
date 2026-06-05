#!/usr/bin/env node
const fs = require('node:fs');
const path = require('node:path');

const cwd = process.cwd();
const isMobileRoot = fs.existsSync(path.join(cwd, 'lib', 'app', 'router', 'app_router.dart'))
  && fs.existsSync(path.join(cwd, 'QA', 'ui_score_scan.js'));
const isProjectRoot = fs.existsSync(path.join(cwd, 'mobile', 'lib', 'app', 'router', 'app_router.dart'))
  && fs.existsSync(path.join(cwd, 'mobile', 'QA', 'ui_score_scan.js'));

if (!isMobileRoot && !isProjectRoot) {
  throw new Error(`无法识别项目根目录，当前目录：${cwd}`);
}

const baseDir = isMobileRoot ? cwd : path.join(cwd, 'mobile');
const mobileDir = path.join(baseDir, 'lib');
const scorePath =
  process.argv[2] || path.join(baseDir, 'QA', 'reports', 'quality_audit_latest.json');
const outputPath = process.argv[3] || null;
const routeJsonOutput = process.argv[4] || null;
const routePath = path.join(mobileDir, 'app', 'router', 'app_router.dart');
const routePathsPath = path.join(mobileDir, 'app', 'router', 'app_route_paths.dart');
const MIN_SCORE = 95;

const readOrThrow = (p, label) => {
  try {
    return fs.readFileSync(p, 'utf8');
  } catch (error) {
    throw new Error(`无法读取 ${label}: ${p}`);
  }
};

const scoreJson = JSON.parse(readOrThrow(scorePath, '质量评分 JSON'));
const scoreMap = new Map();
const scoreRows = scoreJson.pages || scoreJson.rows || [];
for (const item of scoreRows) {
  scoreMap.set(item.page, item);
}

const routePathsContent = readOrThrow(routePathsPath, '路由常量文件');
const routePathConstants = new Map();
for (const match of routePathsContent.matchAll(/static\s+const\s+String\s+(\w+)\s*=\s*'([^']*)';/g)) {
  routePathConstants.set(match[1], match[2]);
}

const resolvePathExpression = (expr) => {
  const raw = expr.trim();
  const rawStripped =
    raw.startsWith("'") && raw.endsWith("'") || raw.startsWith('"') && raw.endsWith('"')
      ? raw.slice(1, -1)
      : raw;

  const interpolationMatch = rawStripped.match(/^\$\{AppRoutePaths\.(\w+)\}(.*)$/);
  if (interpolationMatch) {
    const baseKey = interpolationMatch[1];
    const suffix = interpolationMatch[2] || '';
    const baseValue = routePathConstants.get(baseKey);
    return baseValue ? `${baseValue}${suffix}` : null;
  }

  const appConstMatch = rawStripped.match(/^AppRoutePaths\.(\w+)$/);
  if (appConstMatch) {
    return routePathConstants.get(appConstMatch[1]) || null;
  }

  return rawStripped;
};

const routeContent = readOrThrow(routePath, '路由定义文件');
const routePattern =
  /path\s*:\s*([^,\n]+)[\s\S]*?builder\s*:\s*\([^)]*\)\s*=>\s*(?:const\s+)?([A-Za-z_][A-Za-z0-9_]*)\s*\(/g;

const routeEntries = [];
const seen = new Set();
for (const match of routeContent.matchAll(routePattern)) {
  const pathExpr = match[1].trim();
  const widgetClass = match[2];

  const pathValue = resolvePathExpression(pathExpr);
  if (!pathValue || !pathValue.startsWith('/')) {
    continue;
  }

  const routeKey = `${pathValue}::${widgetClass}`;
  if (seen.has(routeKey)) {
    continue;
  }
  seen.add(routeKey);

  const pathConst = (pathExpr.match(/AppRoutePaths\.(\w+)/) || [])[1] || '';

  routeEntries.push({
    route: pathValue,
    pathConst,
    widgetClass,
  });
}

const classFileMap = new Map();
const walk = (dir, files = []) => {
  for (const item of fs.readdirSync(dir, { withFileTypes: true })) {
    const full = path.join(dir, item.name);
    if (item.isDirectory()) {
      if (item.name === '.dart_tool' || item.name === 'generated') {
        continue;
      }
      walk(full, files);
    } else if (item.isFile() && item.name.endsWith('.dart')) {
      files.push(full);
    }
  }
  return files;
};

const libFiles = walk(mobileDir);
for (const filePath of libFiles) {
  const content = fs.readFileSync(filePath, 'utf8');
  for (const match of content.matchAll(/class\s+([A-Z][A-Za-z0-9_]*)\s+extends\s+/g)) {
    const className = match[1];
    if (!classFileMap.has(className)) {
      classFileMap.set(
        className,
        path.relative(path.join(baseDir), filePath).replaceAll(path.sep, '/'),
      );
    }
  }
}

const routeScoreRows = [];
const missing = [];
let hasViolation = false;

const toViolationLabel = (violations) => {
  if (typeof violations === 'number' || typeof violations === 'string') {
    return String(violations);
  }

  if (violations && typeof violations === 'object') {
    const keys = [
      'forbidden',
      'helper',
      'longText',
      'longTextDensity',
      'action',
      'interactive',
      'interactivePenalty',
      'uiDensity',
      'uiDensityPenalty',
      'totalPenalty',
    ];
    const parts = [];

    for (const key of keys) {
      if (violations[key] !== undefined && violations[key] !== null) {
        parts.push(`${key}=${violations[key]}`);
      }
    }

    const extra = Object.keys(violations).filter((item) => !keys.includes(item) && violations[item] !== undefined);
    if (extra.length > 0) {
      const extraParts = [];
      for (const item of extra.slice(0, 8)) {
        extraParts.push(`${item}=${violations[item]}`);
      }
      parts.push(...extraParts);
    }

    return parts.length > 0 ? parts.join(',') : '-';
  }

  return String(violations || '-');
};

for (const entry of routeEntries) {
  const relFile = classFileMap.get(entry.widgetClass);
  if (!relFile) {
    missing.push({
      ...entry,
      pageFile: '',
      score: null,
      violations: null,
      reason: '无法定位 widget 对应文件',
    });
    hasViolation = true;
    continue;
  }

  const normalizedPage = relFile.replace(/^mobile\//, '').replace(/^lib\//, '');
  const scoreItem = scoreMap.get(normalizedPage);
  if (!scoreItem) {
    missing.push({
      ...entry,
      pageFile: relFile,
      score: null,
      violations: null,
      reason: `路由文件 ${normalizedPage} 不在静态评分结果内`,
    });
    hasViolation = true;
    continue;
  }

  const score = Number(scoreItem.score || 0);
  const violations =
    scoreItem.violations !== undefined && scoreItem.violations !== null
      ? scoreItem.violations
      : scoreItem.totalPenalty || 0;
  const violationsLabel = toViolationLabel(violations);
  const row = {
    route: entry.route,
    pageFile: normalizedPage,
    widgetClass: entry.widgetClass,
    score,
    violations,
    violationsLabel,
    reason: score >= MIN_SCORE ? 'PASS' : `LOW_SCORE(<${MIN_SCORE})`,
  };
  routeScoreRows.push(row);
  if (score < 95) {
    hasViolation = true;
  }
}

routeScoreRows.sort((a, b) => a.route.localeCompare(b.route));
missing.sort((a, b) => a.route.localeCompare(b.route));

const lines = [];
lines.push('| 路由 | 页面文件 | 评分 | 污染命中 | 状态/原因 |');
lines.push('| --- | --- | ---: | ---: | --- |');
for (const row of routeScoreRows) {
  lines.push(`| ${row.route} | ${row.pageFile} | ${row.score} | ${row.violationsLabel} | ${row.reason} |`);
}
for (const row of missing) {
  lines.push(`| ${row.route} | ${row.pageFile || '未映射'} | - | - | ${row.reason} (${row.widgetClass}) |`);
}

const scoredValues = routeScoreRows.map((row) => row.score).filter((value) => Number.isFinite(value));
const minScore = scoredValues.length > 0 ? Math.min(...scoredValues) : 95;
const allPass = !hasViolation;
let summary = `## 路由级评分闭环\n`;
summary += `- 目标路由数: ${routeEntries.length}\n`;
summary += `- 已闭环路由: ${routeScoreRows.length}\n`;
summary += `- 未映射/缺项: ${missing.length}\n`;
summary += `- 全部路由95+：${allPass ? '是' : '否'}\n\n`;
summary += `${lines.join('\n')}\n`;

if (outputPath) {
  fs.writeFileSync(outputPath, summary);
}

const payload = {
  version: 1,
  generatedAt: new Date().toISOString(),
  summary: {
    totalRoutes: routeEntries.length,
    mappedRoutes: routeScoreRows.length,
    missingRoutes: missing.length,
    allPass95: allPass,
    minScore,
  },
  routeScoreRows,
  missing,
};
if (routeJsonOutput) {
  fs.writeFileSync(routeJsonOutput, JSON.stringify(payload, null, 2));
}

if (!routeJsonOutput) {
  process.stdout.write(summary);
}

if (hasViolation) {
  process.exitCode = 2;
}
