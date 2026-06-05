#!/usr/bin/env node
const fs = require('node:fs');
const path = require('node:path');

const mobileDir = fs.existsSync(path.join(process.cwd(), 'test', 'ui_pollution_guard_test.dart'))
  ? process.cwd()
  : path.join(process.cwd(), 'mobile');

const pollutionsPath = path.join(mobileDir, 'test', 'ui_pollution_guard_test.dart');
const pollutionsSource = fs.readFileSync(pollutionsPath, 'utf8');

const forbiddenMatch = pollutionsSource.match(/const _forbiddenUiFragments = \[(.*?)\];/s);
const forbiddenFragments = forbiddenMatch
  ? [...forbiddenMatch[1].matchAll(/'([^']*)'|\"([^\"]*)\"/g)]
    .map((x) => x[1] || x[2])
    .filter(Boolean)
  : [];

const PAGE_FILE_RE = /^(.*_page|attachment_picker_field)\.dart$/;
const pagePenalty = {
  forbidden: 8,
  helper: 2,
  longText: 2,
  action: 2,
  interactive: 3,
  uiDensity: 2,
};
const helperFragments = [
  '说明',
  '提示',
  '清理',
  '稍后',
];
const uiDensityFragments = [
  'IconButton(',
  'TextButton(',
  'FilledButton(',
  'OutlinedButton(',
  'ElevatedButton(',
  'FloatingActionButton(',
  'PopupMenuButton(',
  'SegmentedButton(',
  'showModalBottomSheet',
  'showDialog',
  'AlertDialog(',
  'SimpleDialog(',
  'BottomNavigationBar(',
];
const interactiveFieldFragments = [
  'DropdownButtonFormField',
  'DropdownButton',
  'Switch',
  'Checkbox',
  'CheckboxListTile',
  'Radio',
  'DatePicker',
  'showDatePicker',
  'Slider',
  'SwitchListTile',
  'TextField(',
  'TextFormField(',
  'Chip(',
  'FilterChip(',
  'InputChip(',
  'Switch.adaptive',
];
const longTextThreshold = 32;
const interactiveFieldThreshold = 8;
const uiDensityThreshold = 16;

function extractAppBarActionCount(content) {
  let cursor = 0;
  let total = 0;

  while (true) {
    const barStart = content.indexOf('appBar:', cursor);
    if (barStart === -1) {
      break;
    }

    const appBarStart = content.indexOf('AppBar(', barStart);
    if (appBarStart === -1) {
      cursor = barStart + 'appBar:'.length;
      continue;
    }

    let depth = 0;
    let appBarEnd = appBarStart;
    for (let i = appBarStart; i < content.length; i += 1) {
      const c = content[i];
      if (c === '(') {
        depth += 1;
      }
      if (c === ')') {
        depth -= 1;
        if (depth === 0) {
          appBarEnd = i + 1;
          break;
        }
      }
    }

    const appBarBlock = content.slice(appBarStart, appBarEnd);
    const actionStart = appBarBlock.indexOf('actions:');
    if (actionStart !== -1) {
      const listStart = appBarBlock.indexOf('[', actionStart);
      if (listStart !== -1) {
        let listDepth = 0;
        let listEnd = -1;
        for (let i = listStart; i < appBarBlock.length; i += 1) {
          const ch = appBarBlock[i];
          if (ch === '[') {
            listDepth += 1;
          }
          if (ch === ']') {
            listDepth -= 1;
            if (listDepth === 0) {
              listEnd = i;
              break;
            }
          }
        }

        if (listEnd !== -1) {
          const actionList = appBarBlock.slice(listStart, listEnd);
          total += (actionList.match(/IconButton\(|PopupMenuButton<|PopupMenuButton\(|FilledButton\(|OutlinedButton\(|TextButton\(|FloatingActionButton\(/g) ||
            []).length;
        }
      }
    }

    cursor = appBarEnd;
  }

  return total;
}

function walkDir(baseDir) {
  const queue = [path.join(baseDir, 'lib')];
  const files = [];
  while (queue.length > 0) {
    const item = queue.pop();
    const stat = fs.statSync(item);
    if (stat.isDirectory()) {
      for (const entry of fs.readdirSync(item)) {
        queue.push(path.join(item, entry));
      }
      continue;
    }
    const name = path.basename(item);
    if (!PAGE_FILE_RE.test(name)) {
      continue;
    }
    if (name.endsWith('.g.dart') || name.endsWith('.freezed.dart')) {
      continue;
    }
    files.push(path.relative(path.join(baseDir, 'lib'), item));
  }
  return files.sort();
}

function countTextLiterals(content, maxLen = 20) {
  const withoutComments = removeComments(content);
  let count = 0;
  const regex = /Text\((`(?:[^`]|`{1,2}(?!`))*`|'[^']*'|"[^"]*")/gs;
  for (const match of withoutComments.matchAll(regex)) {
    const raw = match[1];
    const text = raw
      .replace(/^`|`$/g, '')
      .replace(/^'|'$/g, '')
      .replace(/^"|\"$/g, '')
      .trim();
    if (text.includes('${')) {
      continue;
    }
    if (text.length > maxLen) {
      count++;
    }
  }
  return count;
}

function removeComments(content) {
  return content
    .replace(/\/\*[\s\S]*?\*\//g, '')
    .replace(/\/\/.*$/gm, '')
    .replace(/^\s*\/\/.*$/gm, '');
}

function countFragmentMatches(content, fragments) {
  let count = 0;
  const seen = new Map();
  for (const fragment of fragments) {
    const escaped = fragment.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
    const reg = new RegExp(escaped, 'g');
    const hits = content.match(reg) || [];
    const unique = new Set(hits);
    count += unique.size ? unique.size : 0;
    if (unique.size > 0) {
      seen.set(fragment, unique.size);
    }
  }
  return { count, seen };
}

function scorePage(content) {
  const noComments = removeComments(content);
  const forbiddenHits = forbiddenFragments.filter((item) => noComments.includes(item)).length;
  const helperHits = helperFragments.reduce((acc, text) => {
    const reg = new RegExp(text.replace(/[.*+?^${}()|[\]\\]/g, '\\$&'), 'g');
    return acc + ((noComments.match(reg) || []).length);
  }, 0);
  const longTextHits = countTextLiterals(content);
  const actionHits = extractAppBarActionCount(content);
  const interactiveFieldHits = countFragmentMatches(
    noComments,
    interactiveFieldFragments,
  ).count;
  const uiDensityHits = countFragmentMatches(noComments, uiDensityFragments).count;
  const effectiveActionPenalty = Math.max(0, actionHits - 2);
  const interactivePenalty = Math.max(0, interactiveFieldHits - interactiveFieldThreshold);
  const uiDensityPenalty = Math.max(0, uiDensityHits - uiDensityThreshold);
  const longTextDensityPenalty = Math.max(
    0,
    countTextLiteralsWithThreshold(noComments, longTextThreshold) - 2,
  );

  const totalPenalty = forbiddenHits * pagePenalty.forbidden +
    helperHits * pagePenalty.helper +
    longTextHits * pagePenalty.longText +
    effectiveActionPenalty * pagePenalty.action +
    interactivePenalty * pagePenalty.interactive +
    uiDensityPenalty * pagePenalty.uiDensity +
    longTextDensityPenalty * 1;

  const score = Math.max(0, 100 - totalPenalty);
  return {
    score,
    violations: {
      forbidden: forbiddenHits,
      helper: helperHits,
      longText: longTextHits,
      action: actionHits,
      longTextDensity: countTextLiteralsWithThreshold(noComments, longTextThreshold),
      interactive: interactiveFieldHits,
      uiDensity: uiDensityHits,
      interactivePenalty,
      uiDensityPenalty,
      longTextDensityPenalty,
      totalPenalty,
    },
  };
}

function countTextLiteralsWithThreshold(content, maxLen) {
  let count = 0;
  const withoutComments = content;
  const regex = /Text\((`(?:[^`]|`{1,2}(?!`))*`|'[^']*'|"[^"]*")/gs;
  for (const match of withoutComments.matchAll(regex)) {
    const raw = match[1];
    const text = raw
      .replace(/^`|`$/g, '')
      .replace(/^'|'$/g, '')
      .replace(/^"|\"$/g, '')
      .trim();
    if (text.includes('${')) {
      continue;
    }
    if (text.length >= maxLen) {
      count += 1;
    }
  }
  return count;
}

function main() {
  const files = walkDir(mobileDir);
  const results = [];
  for (const file of files) {
    const fullPath = path.join(mobileDir, 'lib', file);
    const content = fs.readFileSync(fullPath, 'utf8');
    const breakdown = scorePage(content);
    results.push({
      page: file,
      score: breakdown.score,
      ...breakdown.violations,
    });
  }

  const sorted = [...results].sort((a, b) => a.score - b.score || b.action - a.action);
  const minScore = Math.min(...sorted.map((item) => item.score));
  const avgScore = sorted.reduce((sum, item) => sum + item.score, 0) / sorted.length;

  const target = process.argv.includes('--json');
  if (target) {
    process.stdout.write(
      JSON.stringify(
        {
          generatedAt: new Date().toISOString(),
          totalPages: results.length,
          average: Number(avgScore.toFixed(2)),
          minScore,
          rows: sorted,
        },
        null,
        2,
      ),
    );
    return;
  }

  console.log('page\tscore\tforbidden\thelper\tlongText\taction');
  for (const item of sorted) {
    console.log(
      `${item.page}\t${item.score}\t${item.forbidden}\t${item.helper}\t${item.longText}\t${item.action}`,
    );
  }
  console.log(`\n总结: 总页数=${results.length}，平均分=${avgScore.toFixed(2)}，最低分=${minScore}`);
}

main();
