import { describe, expect, it } from 'vitest'
import { readFileSync } from 'node:fs'
import { compile, createSSRApp, defineComponent, h } from 'vue'
import { parse } from 'vue/compiler-sfc'
import { renderToString } from 'vue/server-renderer'
import { componentScript } from '@/test/componentScript'
import { parseReportContent, parseReportSnapshot, formatMoney, reportMasked, reportMatches } from '@/utils/aiReportPresentation'
import type { AIReport } from '@/api/ai'

const presentation = () => ({ parseReportContent, formatMoney })

describe('AI report presentation boundaries', () => {
  it('recognizes explicit name handling for the current and historical report prompts', () => {
    for (const version of ['personal-ledger-v3', 'personal-ledger-v4', 'personal-ledger-v5']) {
      const report = { prompt_version: version, report_type: 'monthly', provider_id: 'p', period_start: '2026-10-01', period_end: '2026-10-23' } as AIReport
      expect(reportMasked(report)).toBe(false)
      expect(reportMasked({ ...report, prompt_version: `${version}-masked` })).toBe(true)
      expect(reportMatches(report, { provider_id: 'p', report_type: 'monthly', period_start: '2026-10-01', period_end: '2026-10-23', mask_names: false })).toBe(true)
    }
    expect(reportMasked({ prompt_version: 'unknown' } as AIReport)).toBeNull()
  })

  it('does not present missing or invalid financial facts as a real zero', () => {
    const view = presentation()
    for (const value of [undefined, null, '', 'invalid', Infinity]) expect(view.formatMoney(value)).toBe('—')
    expect(view.formatMoney(0, 'CNY')).toBe('¥0.00')
    expect(view.formatMoney(-20, 'CNY')).toBe('-¥20.00')
  })

  it('does not label malformed or empty structured content as a report', () => {
    const view = presentation()
    for (const value of ['{broken', '{}', '[]', '{"summary":null}', '{"summary":"  "}', 'null']) {
      expect(view.parseReportContent(value)).toBeNull()
    }
    expect(view.parseReportContent('Plain text report')?.summary).toBe('Plain text report')
    expect(view.parseReportContent('{"summary":"Valid summary","highlights":4}')?.highlights).toEqual([])
  })
})

const snapshot = {
  currency: 'CNY', income_total: 500, expense_total: 120, net_cashflow: 380,
  period: { start: '2026-10-20', end: '2026-10-22', timezone: 'Asia/Shanghai' },
  top_expense_categories: [{ name: '餐饮', amount: 120, count: 2 }],
  family_members: [{ display_name: '同名成员', expense_total: 120, count: 2 }],
  account_changes: [{ account_name: '账户1', balance_delta: -120 }],
  budget: {
    monthly_budget: null, spent: 120, remaining: null, used_percent: null,
    period_start: '2026-10-01', period_end: '2026-10-22', settings_basis: 'current_budget_settings',
    member_budgets: [
      { member_name: '同名成员', amount: 300, spent: 120, remaining: 180, percentage: 40 },
      { member_name: '同名成员', category_name: '餐饮', amount: 75, spent: 120, remaining: -45, percentage: 160 },
    ],
    over_budget_categories: [],
  },
}

async function renderSnapshot(value: unknown) {
  const report: AIReport = {
    id: 'synthetic-report', report_type: 'monthly', period_start: '2026-10-20', period_end: '2026-10-22',
    status: 'completed', content_json: '{"summary":"合成测试报告"}', snapshot_json: JSON.stringify(value),
    provider_id: 'synthetic-provider', provider_name: '合成服务', model: 'synthetic-model',
    prompt_version: 'personal-ledger-v3-masked', created_at: '2026-10-22T12:00:00Z', updated_at: '2026-10-22T12:00:00Z',
  }
  const view = componentScript('components/ai/AIReportDocument.vue', [
    'content', 'snapshot', 'maximum', 'money', 'generatedAt', 'chartWidth', 'reportMasked', 'reportPeriod', 'typeText',
  ], {}, { report })
  const { descriptor } = parse(readFileSync('src/components/ai/AIReportDocument.vue', 'utf8'))
  const icon = defineComponent({ render: () => h('span', { 'aria-hidden': true }) })
  const component = defineComponent({
    props: ['report'],
    components: { ChevronDown: icon, ShieldCheck: icon, Sparkles: icon, Wallet: icon },
    setup: () => view.entry,
    render: compile(descriptor.template!.content),
  })
  try {
    return (await renderToString(createSSRApp(component, { report }))).replace(/<!--[\s\S]*?-->/g, '')
  } finally { view.unmount() }
}

describe('AI snapshot scope and unknown values', () => {
  it.each([undefined, null, '', '   '])('does not invent a currency for %s', currency => {
    const parsed = parseReportSnapshot(JSON.stringify({ ...snapshot, currency }))!
    expect(parsed.currency).toBeNull()
    expect(formatMoney(120, parsed.currency)).toBe('120.00（币种未知）')
    expect(formatMoney(-20, parsed.currency)).toBe('-20.00（币种未知）')
  })

  it('requires an explicit currency even when formatting outside a parsed snapshot', () => {
    expect(formatMoney(0)).toBe('0.00（币种未知）')
    expect(formatMoney(120, 'USD')).toBe('USD 120.00')
    expect(formatMoney(null, 'CNY')).toBe('—')
  })

  it.each([undefined, null, {}, 'invalid', [null]])('preserves unknown or malformed arrays (%s) instead of reporting zero', value => {
    const parsed = parseReportSnapshot(JSON.stringify({
      ...snapshot, top_expense_categories: value, family_members: value, account_changes: value,
      budget: { ...snapshot.budget, member_budgets: value },
    }))!
    expect(parsed.categories).toBeNull()
    expect(parsed.members).toBeNull()
    expect(parsed.accounts).toBeNull()
    expect(parsed.budget?.memberBudgets).toBeNull()
  })

  it('keeps valid empty arrays as a known zero', () => {
    const parsed = parseReportSnapshot(JSON.stringify({
      ...snapshot, top_expense_categories: [], family_members: [], account_changes: [],
      budget: { ...snapshot.budget, member_budgets: [] },
    }))!
    expect(parsed.categories).toEqual([])
    expect(parsed.members).toEqual([])
    expect(parsed.accounts).toEqual([])
    expect(parsed.budget?.memberBudgets).toEqual([])
  })

  it('keeps each budget entry and its sent values without merging equal names', () => {
    const parsed = parseReportSnapshot(JSON.stringify(snapshot))!
    expect(parsed.members).toEqual([{ name: '同名成员', amount: 120, count: 2 }])
    expect(parsed.accounts).toEqual([{ name: '账户1', change: -120 }])
    expect(parsed.categories).toEqual([{ name: '餐饮', amount: 120 }])
    expect(parsed.budget?.memberBudgets).toEqual([
      { name: '同名成员', category: '', amount: 300, spent: 120, remaining: 180, percentage: 40 },
      { name: '同名成员', category: '餐饮', amount: 75, spent: 120, remaining: -45, percentage: 160 },
    ])
  })

  it('renders expense people and budget entries separately, including budget-only members', async () => {
    const html = await renderSnapshot({ ...snapshot, family_members: [] })
    expect(html).toMatch(/成员支出人数<\/dt>\s*<dd>0<\/dd>/)
    expect(html).toMatch(/成员预算条目<\/dt>\s*<dd>2<\/dd>/)
    expect(html).toContain('同名成员')
    expect(html).toContain('¥300.00')
    expect(html).toContain('¥75.00')
    expect(html).toContain('¥180.00')
    expect(html).toContain('-¥45.00')
    expect(html).toContain('160%')
  })

  it('renders missing scope arrays and currency as unknown without an inferred count', async () => {
    const html = await renderSnapshot({ income_total: 120 })
    for (const label of ['成员支出人数', '成员预算条目', '账户数量', '支出分类条目', '统计币种']) {
      expect(html).toMatch(new RegExp(`${label}</dt>\\s*<dd>未知</dd>`))
    }
    expect(html).toContain('120.00（币种未知）')
    expect(html).not.toContain('¥')
  })

  it('renders genuine empty arrays as zero rather than unknown', async () => {
    const html = await renderSnapshot({
      ...snapshot, family_members: [], account_changes: [], top_expense_categories: [],
      budget: { ...snapshot.budget, member_budgets: [] },
    })
    for (const label of ['成员支出人数', '成员预算条目', '账户数量', '支出分类条目']) {
      expect(html).toMatch(new RegExp(`${label}</dt>\\s*<dd>0</dd>`))
    }
    expect(html).toMatch(/统计币种<\/dt>\s*<dd>CNY<\/dd>/)
  })

  it('does not call an unrecorded budget usage rate an unset budget', async () => {
    const html = await renderSnapshot({ ...snapshot, budget: { monthly_budget: 500, spent: 120 } })
    expect(html).toContain('使用率未知')
    expect(html).not.toContain('未设总预算')
    expect(await renderSnapshot(snapshot)).toContain('未设总预算')
  })
})
