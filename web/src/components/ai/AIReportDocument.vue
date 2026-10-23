<script setup lang="ts">
import { computed } from 'vue'
import { ChevronDown, ShieldCheck, Sparkles, Wallet } from '@lucide/vue'
import type { AIReport } from '@/api/ai'
import { chartWidth, formatMoney, parseReportContent, parseReportSnapshot, reportMasked, reportPeriod, typeText } from '@/utils/aiReportPresentation'

const props = defineProps<{ report: AIReport }>()
const content = computed(() => props.report.status === 'completed' ? parseReportContent(props.report.content_json) : null)
const snapshot = computed(() => parseReportSnapshot(props.report.snapshot_json))
const maximum = computed(() => Math.max(0, ...(snapshot.value?.categories?.map(item => item.amount ?? 0) || [])))
const money = (value: unknown) => formatMoney(value, snapshot.value?.currency)
const generatedAt = computed(() => {
  const date = new Date(props.report.created_at)
  return Number.isFinite(date.getTime()) ? date.toLocaleString('zh-CN', { year: 'numeric', month: '2-digit', day: '2-digit', hour: '2-digit', minute: '2-digit', hour12: false }) : ''
})
</script>

<template>
  <article class="ai-document" data-testid="ai-report-document">
    <header class="ai-document-intro">
      <h2>{{ content?.title || typeText(report.report_type) }}</h2>
      <div class="ai-report-meta"><span class="ai-status">{{ content ? '已完成' : '内容不可用' }}</span><time v-if="generatedAt" :datetime="report.created_at">{{ generatedAt }} 生成</time><span>{{ report.provider_name }} · {{ report.model }}</span></div>
      <dl v-if="snapshot" class="ai-facts">
        <div><dt>收入</dt><dd>{{ money(snapshot.income) }}</dd></div>
        <div><dt>支出</dt><dd>{{ money(snapshot.expense) }}</dd></div>
        <div><dt>结余</dt><dd :class="{ 'ai-positive': snapshot.net !== null && snapshot.net > 0, 'ai-negative': snapshot.net !== null && snapshot.net < 0 }">{{ money(snapshot.net) }}</dd></div>
      </dl>
      <p v-if="snapshot" class="ai-facts-note"><Wallet :size="13" />以上为账本汇总，不是 AI 估算</p>
    </header>
    <div class="ai-document-content">
      <section class="ai-report-section">
        <h3><Sparkles :size="17" />AI 解读</h3>
        <p v-if="content" class="ai-prose">{{ content.summary }}</p>
        <p v-else role="alert" class="ai-prose">这份记录没有可读取的完整分析内容，不作为有效结论。可以查看数据快照，或重新生成。</p>
        <ul v-if="content?.highlights.length" class="ai-highlights"><li v-for="(item, index) in content.highlights" :key="index">{{ item }}</li></ul>
      </section>
      <div v-if="snapshot && (snapshot.categories?.length || snapshot.budget)" class="ai-data-area">
        <section v-if="snapshot.categories?.length" aria-label="支出构成">
          <h3>主要支出分类</h3>
          <div class="ai-bars">
            <div v-for="(item, index) in snapshot.categories" :key="index" class="ai-bar-row">
              <span class="ai-bar-name" :title="item.name">{{ item.name }}</span><span class="ai-bar-track" aria-hidden="true"><i :style="{ width: chartWidth(item.amount, maximum) }" /></span><span class="ai-bar-value">{{ money(item.amount) }}</span>
            </div>
          </div>
        </section>
        <section v-if="snapshot.budget" aria-label="预算使用">
          <h3>总预算使用</h3>
          <p class="ai-budget-number">{{ snapshot.budget.used === null ? (snapshot.budget.totalUnset ? '未设总预算' : '使用率未知') : `${snapshot.budget.used}%` }}<small v-if="snapshot.budget.used !== null">已使用</small></p>
          <div v-if="snapshot.budget.used !== null" class="ai-budget-track" aria-hidden="true"><i :class="{ 'is-over': snapshot.budget.used > 100 }" :style="{ width: chartWidth(snapshot.budget.used, 100) }" /></div>
          <div class="ai-budget-caption"><span>已用 {{ money(snapshot.budget.spent) }}</span><span v-if="snapshot.budget.remaining !== null">{{ snapshot.budget.remaining < 0 ? '超出' : '剩余' }} {{ money(Math.abs(snapshot.budget.remaining)) }}</span></div>
          <p v-if="snapshot.budget.start && snapshot.budget.end" class="ai-caption">{{ snapshot.budget.start }} 至 {{ snapshot.budget.end }}<template v-if="snapshot.budget.basis === 'current_budget_settings'"> · 按生成时的预算设置计算</template></p>
        </section>
      </div>
      <section v-if="content?.risks.length" class="ai-report-section ai-following">
        <h3>需要留意</h3>
        <ul class="ai-risk-list"><li v-for="(risk, index) in content.risks" :key="index"><strong>{{ risk.title || '风险提示' }}</strong><p class="ai-prose">{{ risk.detail }}</p></li></ul>
      </section>
      <section v-if="content?.suggestions.length" class="ai-report-section ai-following">
        <h3>建议</h3><ul class="ai-suggestions"><li v-for="(item, index) in content.suggestions" :key="index">{{ item }}</li></ul>
      </section>
    </div>
    <details class="ai-snapshot">
      <summary><span><ShieldCheck :size="16" />本次使用的数据</span><ChevronDown :size="16" /></summary>
      <div class="ai-snapshot-body">
        <p>生成时的快照，不随当前账本变化。</p>
        <dl class="ai-scope-list">
          <div><dt>收支周期</dt><dd>{{ reportPeriod(report) }}</dd></div>
          <div><dt>名称处理</dt><dd>{{ reportMasked(report) === true ? '已替换成员和账户名称' : reportMasked(report) === false ? '保留原始名称' : '未记录，无法确认' }}</dd></div>
          <div><dt>成员支出人数</dt><dd>{{ snapshot?.members?.length ?? '未知' }}</dd></div>
          <div><dt>成员预算条目</dt><dd>{{ snapshot?.budget?.memberBudgets?.length ?? '未知' }}</dd></div>
          <div><dt>账户数量</dt><dd>{{ snapshot?.accounts?.length ?? '未知' }}</dd></div>
          <div><dt>支出分类条目</dt><dd>{{ snapshot?.categories?.length ?? '未知' }}</dd></div>
          <div><dt>统计币种</dt><dd>{{ snapshot?.currency || '未知' }}</dd></div>
          <div v-if="snapshot?.period.timezone"><dt>统计时区</dt><dd>{{ snapshot.period.timezone }}</dd></div>
        </dl>
        <p v-if="!snapshot">此报告未提供可读取的数据快照，不能推断为零收支。</p>
        <template v-else>
          <details v-if="snapshot.members?.length" class="ai-disclosure"><summary>成员支出 <ChevronDown :size="15" /></summary><dl class="ai-scope-list"><div v-for="(member, index) in snapshot.members" :key="index"><dt>{{ member.name }}</dt><dd>{{ money(member.amount) }}</dd></div></dl></details>
          <details v-if="snapshot.budget?.memberBudgets?.length" class="ai-disclosure">
            <summary>成员预算明细 <ChevronDown :size="15" /></summary>
            <p class="ai-caption">按实际发送的预算条目列出，同名不合并；条目数不代表总人数。</p>
            <p v-if="snapshot.budget.start && snapshot.budget.end" class="ai-caption">预算周期：{{ snapshot.budget.start }} 至 {{ snapshot.budget.end }}</p>
            <dl class="ai-scope-list">
              <div v-for="(memberBudget, index) in snapshot.budget.memberBudgets" :key="index">
                <dt>{{ memberBudget.name }}<template v-if="memberBudget.category"><br />{{ memberBudget.category }}</template></dt>
                <dd>预算 {{ money(memberBudget.amount) }}<br />已用 {{ money(memberBudget.spent) }}<br />剩余 {{ money(memberBudget.remaining) }}<br />使用率 {{ memberBudget.percentage === null ? '未知' : `${memberBudget.percentage}%` }}</dd>
              </div>
            </dl>
          </details>
          <details v-if="snapshot.accounts?.length" class="ai-disclosure"><summary>账户净变化 <ChevronDown :size="15" /></summary><dl class="ai-scope-list"><div v-for="(account, index) in snapshot.accounts" :key="index"><dt>{{ account.name }}</dt><dd>{{ money(account.change) }}</dd></div></dl></details>
        </template>
        <p class="ai-caption">分类名称会随汇总发送；不包含交易备注和附件。</p>
      </div>
    </details>
  </article>
</template>
