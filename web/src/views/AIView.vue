<script setup lang="ts">
import { computed, onMounted, reactive, ref } from 'vue'
import { useRouter } from 'vue-router'
import { AlertTriangle, ArrowLeft, Bot, CalendarClock, KeyRound, PlayCircle, RefreshCw, ShieldCheck, Sparkles, Trash2, TrendingUp, Zap } from 'lucide-vue-next'
import { aiApi, type AIProvider, type AIProviderPreset, type AIReport, type AIReportScheduleRunResult } from '@/api/ai'
import { toast } from '@/composables/useToast'

const router = useRouter()
const loading = ref(false)
const saving = ref(false)
const testingId = ref<string | null>(null)
const generating = ref(false)
const savingSchedule = ref(false)
const triggeringSchedule = ref(false)
const providers = ref<AIProvider[]>([])
const providerPresets = ref<AIProviderPreset[]>([])
const reports = ref<AIReport[]>([])
const selectedReport = ref<AIReport | null>(null)
const selectedPresetId = ref('deepseek')
const scheduleResults = ref<AIReportScheduleRunResult[]>([])

const providerForm = reactive({
  name: 'DeepSeek',
  base_url: 'https://api.deepseek.com',
  api_key: '',
  model: 'deepseek-chat',
  enabled: true
})

const reportForm = reactive({
  report_type: 'weekly',
  provider_id: '',
  period_start: defaultWeekStart(),
  period_end: defaultWeekEnd()
})

const scheduleForm = reactive({
  enabled: false,
  weekly_enabled: true,
  monthly_enabled: true,
  hour: 8,
  last_weekly_run: '',
  last_monthly_run: ''
})

const enabledProviders = computed(() => providers.value.filter(provider => provider.enabled))
const selectedPreset = computed(() => providerPresets.value.find(preset => preset.id === selectedPresetId.value))
const reportContent = computed(() => parseReportContent(selectedReport.value?.content_json))
const reportSnapshot = computed(() => parseReportSnapshot(selectedReport.value?.snapshot_json))
const reportRisks = computed(() => Array.isArray(reportContent.value?.risks) ? reportContent.value.risks : [])
const snapshotBudget = computed(() => reportSnapshot.value?.budget || null)
const snapshotMembers = computed(() => Array.isArray(reportSnapshot.value?.family_members) ? reportSnapshot.value.family_members.slice(0, 4) : [])

onMounted(loadData)

async function loadData() {
  loading.value = true
  try {
    const [presetList, providerList, reportList] = await Promise.all([
      aiApi.listProviderPresets(),
      aiApi.listProviders(),
      aiApi.listReports()
    ])
    const schedule = await aiApi.getScheduleSettings()
    providerPresets.value = presetList
    providers.value = providerList
    reports.value = reportList
    Object.assign(scheduleForm, {
      enabled: schedule.enabled,
      weekly_enabled: schedule.weekly_enabled,
      monthly_enabled: schedule.monthly_enabled,
      hour: schedule.hour,
      last_weekly_run: schedule.last_weekly_run || '',
      last_monthly_run: schedule.last_monthly_run || ''
    })
    reportForm.provider_id ||= enabledProviders.value[0]?.id || ''
    selectedReport.value = reportList[0] || null
  } catch (error: any) {
    toast.error(error.message || 'AI 数据加载失败')
  } finally {
    loading.value = false
  }
}

async function saveSchedule() {
  savingSchedule.value = true
  try {
    const schedule = await aiApi.updateScheduleSettings({
      enabled: scheduleForm.enabled,
      weekly_enabled: scheduleForm.weekly_enabled,
      monthly_enabled: scheduleForm.monthly_enabled,
      hour: Number(scheduleForm.hour),
      last_weekly_run: scheduleForm.last_weekly_run || undefined,
      last_monthly_run: scheduleForm.last_monthly_run || undefined
    })
    Object.assign(scheduleForm, {
      enabled: schedule.enabled,
      weekly_enabled: schedule.weekly_enabled,
      monthly_enabled: schedule.monthly_enabled,
      hour: schedule.hour,
      last_weekly_run: schedule.last_weekly_run || '',
      last_monthly_run: schedule.last_monthly_run || ''
    })
    toast.success('自动报告设置已保存')
  } catch (error: any) {
    toast.error(error.message || '保存自动报告设置失败')
  } finally {
    savingSchedule.value = false
  }
}

async function triggerSchedule() {
  triggeringSchedule.value = true
  try {
    const payload = await aiApi.triggerSchedule()
    scheduleResults.value = payload.results || []
    const successCount = scheduleResults.value.reduce((sum, item) => sum + item.succeeded, 0)
    toast.success(successCount > 0 ? `已生成 ${successCount} 份自动报告` : '自动报告检查完成')
    await loadData()
  } catch (error: any) {
    toast.error(error.message || '触发自动报告失败')
  } finally {
    triggeringSchedule.value = false
  }
}

function applyProviderPreset(preset: AIProviderPreset) {
  selectedPresetId.value = preset.id
  providerForm.name = preset.name
  providerForm.base_url = preset.base_url
  providerForm.model = preset.model
  providerForm.enabled = true
}

async function saveProvider() {
  if (!providerForm.name.trim() || !providerForm.base_url.trim() || !providerForm.model.trim()) {
    toast.error('请完整填写 Provider 信息')
    return
  }
  saving.value = true
  try {
    await aiApi.createProvider({
      name: providerForm.name.trim(),
      provider_type: 'openai_compatible',
      base_url: providerForm.base_url.trim(),
      api_key: providerForm.api_key.trim(),
      model: providerForm.model.trim(),
      enabled: providerForm.enabled
    })
    providerForm.api_key = ''
    toast.success('Provider 已保存')
    await loadData()
  } catch (error: any) {
    toast.error(error.message || '保存失败')
  } finally {
    saving.value = false
  }
}

async function testProvider(provider: AIProvider) {
  testingId.value = provider.id
  try {
    await aiApi.testProvider(provider.id)
    toast.success('连接测试通过')
  } catch (error: any) {
    toast.error(error.message || '连接测试失败')
  } finally {
    testingId.value = null
  }
}

async function deleteProvider(provider: AIProvider) {
  if (!confirm(`删除 Provider「${provider.name}」？已生成报告不会删除。`)) return
  try {
    await aiApi.deleteProvider(provider.id)
    toast.success('Provider 已删除')
    await loadData()
  } catch (error: any) {
    toast.error(error.message || '删除失败')
  }
}

async function generateReport() {
  generating.value = true
  try {
    const report = await aiApi.generateReport({
      report_type: reportForm.report_type,
      provider_id: reportForm.provider_id || undefined,
      period_start: reportForm.period_start,
      period_end: reportForm.period_end
    })
    selectedReport.value = report
    toast.success('AI 报告已生成')
    await loadData()
  } catch (error: any) {
    toast.error(error.message || '报告生成失败')
  } finally {
    generating.value = false
  }
}

async function deleteReport(report: AIReport) {
  if (!confirm('删除这份 AI 报告？')) return
  try {
    await aiApi.deleteReport(report.id)
    toast.success('报告已删除')
    selectedReport.value = null
    await loadData()
  } catch (error: any) {
    toast.error(error.message || '删除失败')
  }
}

function parseReportContent(content?: string) {
  if (!content) return null
  try {
    return JSON.parse(content)
  } catch {
    return { summary: content }
  }
}

function parseReportSnapshot(snapshot?: string) {
  if (!snapshot) return null
  try {
    return JSON.parse(snapshot)
  } catch {
    return null
  }
}

function statusText(status: string) {
  return ({ completed: '已完成', running: '生成中', failed: '失败', pending: '待处理' } as Record<string, string>)[status] || status
}

function typeText(type: string) {
  return ({ weekly: '每周总结', monthly: '月度总结', family: '家庭分析', budget: '预算建议' } as Record<string, string>)[type] || '财务分析'
}

function scheduleResultText(result: AIReportScheduleRunResult) {
  return `${typeText(result.report_type)} ${result.period_start} - ${result.period_end}，成功 ${result.succeeded}，跳过 ${result.skipped}，失败 ${result.failed}`
}

function shortDate(value: string) {
  return value?.slice(0, 10) || ''
}

function formatMoney(value: unknown) {
  return `¥${Number(value || 0).toFixed(2)}`
}

function riskLevelClass(level?: string) {
  if (level === 'high') return 'border-rose-200 bg-rose-50 text-rose-700 dark:border-rose-400/30 dark:bg-rose-400/10 dark:text-rose-200'
  if (level === 'medium') return 'border-amber-200 bg-amber-50 text-amber-700 dark:border-amber-400/30 dark:bg-amber-400/10 dark:text-amber-200'
  return 'border-emerald-200 bg-emerald-50 text-emerald-700 dark:border-emerald-400/30 dark:bg-emerald-400/10 dark:text-emerald-200'
}

function defaultWeekStart() {
  const date = new Date()
  const day = date.getDay() || 7
  date.setDate(date.getDate() - day + 1)
  return date.toISOString().slice(0, 10)
}

function defaultWeekEnd() {
  const date = new Date(defaultWeekStart())
  date.setDate(date.getDate() + 6)
  return date.toISOString().slice(0, 10)
}
</script>

<template>
  <div class="min-h-full bg-[#F2F2F7] dark:bg-black text-gray-900 dark:text-white">
    <div class="max-w-7xl mx-auto px-4 py-6 space-y-6">
      <header class="flex items-center justify-between gap-4">
        <div class="flex items-center gap-3">
          <button class="p-2 rounded-full hover:bg-black/5 dark:hover:bg-white/10" @click="router.back()">
            <ArrowLeft :size="22" />
          </button>
          <div>
            <h1 class="text-2xl font-bold">AI 分析</h1>
            <p class="text-sm text-gray-500 dark:text-gray-400">OpenAI-compatible Provider、聚合快照和周报/月报管理。</p>
          </div>
        </div>
        <button class="inline-flex items-center gap-2 px-4 py-2 rounded-xl bg-white/80 dark:bg-white/10 border border-black/5 dark:border-white/10" @click="loadData">
          <RefreshCw :size="16" />
          刷新
        </button>
      </header>

      <section class="grid grid-cols-1 lg:grid-cols-[420px_1fr] gap-6">
        <div class="space-y-6">
          <form class="rounded-2xl bg-white/90 dark:bg-[#1C1C1E]/90 border border-black/5 dark:border-white/10 p-5 space-y-4" @submit.prevent="saveProvider">
            <div class="flex items-center gap-2">
              <KeyRound :size="18" />
              <h2 class="font-semibold">Provider 配置</h2>
            </div>
            <div v-if="providerPresets.length" class="grid grid-cols-2 gap-2">
              <button
                v-for="preset in providerPresets"
                :key="preset.id"
                type="button"
                class="min-h-14 rounded-xl border px-3 py-2 text-left transition"
                :class="selectedPresetId === preset.id ? 'border-primary bg-primary/10 text-primary' : 'border-black/5 dark:border-white/10 bg-gray-100/70 dark:bg-white/5'"
                @click="applyProviderPreset(preset)"
              >
                <span class="flex items-center gap-2 text-sm font-medium">
                  <Sparkles :size="14" />
                  {{ preset.name }}
                </span>
                <span class="mt-1 block truncate text-xs opacity-70">{{ preset.model }}</span>
              </button>
            </div>
            <input v-model="providerForm.name" autocomplete="off" class="w-full px-3 py-3 rounded-xl bg-gray-100 dark:bg-white/10 outline-none" placeholder="名称" />
            <input v-model="providerForm.base_url" autocomplete="url" class="w-full px-3 py-3 rounded-xl bg-gray-100 dark:bg-white/10 outline-none" placeholder="Base URL" />
            <select v-if="selectedPreset && selectedPreset.id !== 'openai-compatible'" v-model="providerForm.model" class="w-full px-3 py-3 rounded-xl bg-gray-100 dark:bg-white/10 outline-none">
              <option
                v-for="model in selectedPreset.models"
                :key="model"
                :value="model"
              >
                {{ model }}
              </option>
            </select>
            <input v-else v-model="providerForm.model" autocomplete="off" class="w-full px-3 py-3 rounded-xl bg-gray-100 dark:bg-white/10 outline-none" placeholder="模型，例如 deepseek-chat" />
            <input v-model="providerForm.api_key" type="password" autocomplete="new-password" class="w-full px-3 py-3 rounded-xl bg-gray-100 dark:bg-white/10 outline-none" placeholder="API Key，保存后不会回显" />
            <label class="flex items-center gap-2 text-sm">
              <input v-model="providerForm.enabled" type="checkbox" />
              启用
            </label>
            <button class="w-full py-3 rounded-xl bg-primary text-white font-medium disabled:opacity-60" :disabled="saving">
              {{ saving ? '保存中...' : '保存 Provider' }}
            </button>
          </form>

          <form class="rounded-2xl bg-white/90 dark:bg-[#1C1C1E]/90 border border-black/5 dark:border-white/10 p-5 space-y-4" @submit.prevent="generateReport">
            <div class="flex items-center gap-2">
              <Bot :size="18" />
              <h2 class="font-semibold">生成报告</h2>
            </div>
            <select v-model="reportForm.report_type" class="w-full px-3 py-3 rounded-xl bg-gray-100 dark:bg-white/10 outline-none">
              <option value="weekly">每周总结</option>
              <option value="monthly">月度总结</option>
              <option value="family">家庭分析</option>
              <option value="budget">预算建议</option>
            </select>
            <select v-model="reportForm.provider_id" class="w-full px-3 py-3 rounded-xl bg-gray-100 dark:bg-white/10 outline-none">
              <option value="">自动选择启用 Provider</option>
              <option v-for="provider in enabledProviders" :key="provider.id" :value="provider.id">
                {{ provider.name }} / {{ provider.model }}
              </option>
            </select>
            <div class="grid grid-cols-2 gap-3">
              <input v-model="reportForm.period_start" type="date" class="px-3 py-3 rounded-xl bg-gray-100 dark:bg-white/10 outline-none" />
              <input v-model="reportForm.period_end" type="date" class="px-3 py-3 rounded-xl bg-gray-100 dark:bg-white/10 outline-none" />
            </div>
            <button class="w-full inline-flex items-center justify-center gap-2 py-3 rounded-xl bg-primary text-white font-medium disabled:opacity-60" :disabled="generating">
              <PlayCircle :size="18" />
              {{ generating ? '生成中...' : '生成 AI 报告' }}
            </button>
          </form>

          <form class="rounded-2xl bg-white/90 dark:bg-[#1C1C1E]/90 border border-black/5 dark:border-white/10 p-5 space-y-4" @submit.prevent="saveSchedule">
            <div class="flex items-center justify-between gap-3">
              <div class="flex items-center gap-2">
                <CalendarClock :size="18" />
                <h2 class="font-semibold">自动报告</h2>
              </div>
              <span class="rounded-full px-2.5 py-1 text-xs font-medium" :class="scheduleForm.enabled ? 'bg-emerald-100 text-emerald-700 dark:bg-emerald-400/10 dark:text-emerald-200' : 'bg-gray-100 text-gray-500 dark:bg-white/10 dark:text-gray-400'">
                {{ scheduleForm.enabled ? '已开启' : '默认关闭' }}
              </span>
            </div>
            <label class="flex items-center justify-between gap-3 rounded-xl bg-gray-100/80 px-3 py-3 text-sm dark:bg-white/10">
              <span>
                <span class="block font-medium">启用自动生成</span>
                <span class="block text-xs text-gray-500">仅发送聚合快照，仍不包含交易备注和附件。</span>
              </span>
              <input v-model="scheduleForm.enabled" type="checkbox" class="h-5 w-5" />
            </label>
            <div class="grid grid-cols-2 gap-3">
              <label class="flex items-center gap-2 rounded-xl bg-gray-100/80 px-3 py-3 text-sm dark:bg-white/10">
                <input v-model="scheduleForm.weekly_enabled" type="checkbox" />
                每周总结
              </label>
              <label class="flex items-center gap-2 rounded-xl bg-gray-100/80 px-3 py-3 text-sm dark:bg-white/10">
                <input v-model="scheduleForm.monthly_enabled" type="checkbox" />
                月度总结
              </label>
            </div>
            <label class="block text-sm">
              <span class="mb-2 block text-gray-500">运行小时</span>
              <input v-model.number="scheduleForm.hour" type="number" min="0" max="23" class="w-full rounded-xl bg-gray-100 px-3 py-3 outline-none dark:bg-white/10" />
            </label>
            <div class="grid grid-cols-2 gap-3 text-xs text-gray-500">
              <span>周报上次检查：{{ scheduleForm.last_weekly_run || '无' }}</span>
              <span>月报上次检查：{{ scheduleForm.last_monthly_run || '无' }}</span>
            </div>
            <div v-if="scheduleResults.length" class="space-y-2 rounded-xl bg-gray-100/80 p-3 text-xs text-gray-600 dark:bg-white/10 dark:text-gray-300">
              <p v-for="result in scheduleResults" :key="`${result.report_type}-${result.period_start}`">
                {{ scheduleResultText(result) }}
              </p>
            </div>
            <div class="grid grid-cols-2 gap-3">
              <button class="inline-flex items-center justify-center gap-2 rounded-xl bg-primary py-3 font-medium text-white disabled:opacity-60" :disabled="savingSchedule">
                <CalendarClock :size="17" />
                {{ savingSchedule ? '保存中...' : '保存设置' }}
              </button>
              <button type="button" class="inline-flex items-center justify-center gap-2 rounded-xl border border-black/5 bg-gray-100 py-3 font-medium dark:border-white/10 dark:bg-white/10 disabled:opacity-60" :disabled="triggeringSchedule" @click="triggerSchedule">
                <Zap :size="17" />
                {{ triggeringSchedule ? '触发中...' : '立即触发' }}
              </button>
            </div>
          </form>
        </div>

        <div class="space-y-6">
          <section class="rounded-2xl bg-white/90 dark:bg-[#1C1C1E]/90 border border-black/5 dark:border-white/10 overflow-hidden">
            <div class="p-5 border-b border-black/5 dark:border-white/10 font-semibold">Provider 列表</div>
            <div v-if="loading" class="p-6 text-center text-gray-500">加载中...</div>
            <div v-else-if="providers.length === 0" class="p-6 text-center text-gray-500">暂无 Provider</div>
            <div v-for="provider in providers" v-else :key="provider.id" class="flex items-center gap-4 p-4 border-b border-black/5 dark:border-white/10">
              <span class="w-10 h-10 rounded-full bg-cyan-100 text-cyan-700 flex items-center justify-center"><Bot :size="18" /></span>
              <span class="flex-1 min-w-0">
                <span class="block font-medium truncate">{{ provider.name }}</span>
                <span class="block text-sm text-gray-500 truncate">{{ provider.base_url }} / {{ provider.model }}</span>
              </span>
              <span class="text-xs px-2 py-1 rounded-full" :class="provider.enabled ? 'bg-emerald-100 text-emerald-700' : 'bg-gray-100 text-gray-500'">
                {{ provider.enabled ? '启用' : '停用' }}
              </span>
              <button class="px-3 py-2 rounded-lg bg-gray-100 dark:bg-white/10" @click="testProvider(provider)">
                {{ testingId === provider.id ? '测试中' : '测试' }}
              </button>
              <button class="p-2 rounded-lg hover:bg-red-50 text-red-500" @click="deleteProvider(provider)">
                <Trash2 :size="16" />
              </button>
            </div>
          </section>

          <section class="grid grid-cols-1 xl:grid-cols-[360px_1fr] gap-6">
            <div class="rounded-2xl bg-white/90 dark:bg-[#1C1C1E]/90 border border-black/5 dark:border-white/10 overflow-hidden">
              <div class="p-5 border-b border-black/5 dark:border-white/10 font-semibold">报告历史</div>
              <button
                v-for="report in reports"
                :key="report.id"
                class="w-full text-left p-4 border-b border-black/5 dark:border-white/10 hover:bg-black/5 dark:hover:bg-white/5"
                :class="selectedReport?.id === report.id ? 'bg-primary/10' : ''"
                @click="selectedReport = report"
              >
                <span class="block font-medium">{{ typeText(report.report_type) }}</span>
                <span class="block text-sm text-gray-500">{{ shortDate(report.period_start) }} - {{ shortDate(report.period_end) }}</span>
                <span class="block text-xs text-gray-400">{{ statusText(report.status) }} · {{ report.model }}</span>
              </button>
              <div v-if="reports.length === 0" class="p-6 text-center text-gray-500">暂无报告</div>
            </div>

            <div class="rounded-2xl bg-white/90 dark:bg-[#1C1C1E]/90 border border-black/5 dark:border-white/10 p-5 min-h-[320px]">
              <div v-if="!selectedReport" class="h-full flex items-center justify-center text-gray-500">选择一份报告查看详情</div>
              <div v-else class="space-y-4">
                <div class="flex items-start justify-between gap-4">
                  <div>
                    <h2 class="text-xl font-bold">{{ reportContent?.title || typeText(selectedReport.report_type) }}</h2>
                    <p class="text-sm text-gray-500">{{ selectedReport.provider_name }} / {{ selectedReport.model }}</p>
                  </div>
                  <button class="p-2 rounded-lg hover:bg-red-50 text-red-500" @click="deleteReport(selectedReport)">
                    <Trash2 :size="16" />
                  </button>
                </div>
                <p class="text-gray-700 dark:text-gray-300 leading-7">{{ reportContent?.summary || selectedReport.error_message || '暂无内容' }}</p>
                <div v-if="reportSnapshot" class="grid grid-cols-1 gap-3 md:grid-cols-3">
                  <div class="rounded-2xl border border-black/5 bg-gray-50/90 p-4 dark:border-white/10 dark:bg-white/[0.04]">
                    <div class="flex items-center gap-2 text-xs text-gray-500">
                      <TrendingUp :size="15" />
                      <span>净现金流</span>
                    </div>
                    <p class="mt-2 text-2xl font-black tabular-nums">{{ formatMoney(reportSnapshot.net_cashflow) }}</p>
                    <p class="mt-1 text-xs text-gray-500">收入 {{ formatMoney(reportSnapshot.income_total) }}</p>
                  </div>
                  <div class="rounded-2xl border border-black/5 bg-gray-50/90 p-4 dark:border-white/10 dark:bg-white/[0.04]">
                    <div class="flex items-center gap-2 text-xs text-gray-500">
                      <ShieldCheck :size="15" />
                      <span>预算使用</span>
                    </div>
                    <p class="mt-2 text-2xl font-black tabular-nums">{{ snapshotBudget?.used_percent ?? 0 }}%</p>
                    <p class="mt-1 text-xs text-gray-500">已用 {{ formatMoney(snapshotBudget?.spent) }}</p>
                  </div>
                  <div class="rounded-2xl border border-black/5 bg-gray-50/90 p-4 dark:border-white/10 dark:bg-white/[0.04]">
                    <div class="flex items-center gap-2 text-xs text-gray-500">
                      <Bot :size="15" />
                      <span>发送范围</span>
                    </div>
                    <p class="mt-2 text-2xl font-black tabular-nums">{{ snapshotMembers.length }}</p>
                    <p class="mt-1 text-xs text-gray-500">仅聚合数据，无交易备注</p>
                  </div>
                </div>
                <div v-if="reportContent?.highlights?.length" class="space-y-2">
                  <h3 class="font-semibold">重点</h3>
                  <ul class="list-disc pl-5 text-sm text-gray-600 dark:text-gray-300">
                    <li v-for="item in reportContent.highlights" :key="item">{{ item }}</li>
                  </ul>
                </div>
                <div v-if="reportRisks.length" class="space-y-2">
                  <h3 class="font-semibold">风险</h3>
                  <div class="grid grid-cols-1 gap-3 md:grid-cols-2">
                    <div
                      v-for="risk in reportRisks"
                      :key="risk.title || risk.detail"
                      class="rounded-2xl border p-4"
                      :class="riskLevelClass(risk.level)"
                    >
                      <div class="flex items-start gap-2">
                        <AlertTriangle :size="17" class="mt-0.5 shrink-0" />
                        <div class="min-w-0">
                          <p class="font-semibold">{{ risk.title || '风险提示' }}</p>
                          <p class="mt-1 text-sm opacity-80">{{ risk.detail || risk }}</p>
                        </div>
                      </div>
                    </div>
                  </div>
                </div>
                <div v-if="snapshotMembers.length" class="space-y-2">
                  <h3 class="font-semibold">家庭成员快照</h3>
                  <div class="grid grid-cols-1 gap-3 md:grid-cols-2">
                    <div
                      v-for="member in snapshotMembers"
                      :key="member.display_name"
                      class="rounded-2xl border border-black/5 bg-gray-50/90 p-4 dark:border-white/10 dark:bg-white/[0.04]"
                    >
                      <div class="flex items-center justify-between gap-3">
                        <span class="font-medium">{{ member.display_name || '成员' }}</span>
                        <span class="text-sm font-semibold tabular-nums">{{ formatMoney(member.expense_total) }}</span>
                      </div>
                      <p class="mt-1 text-xs text-gray-500">{{ member.count || 0 }} 笔支出</p>
                    </div>
                  </div>
                </div>
                <div v-if="reportContent?.suggestions?.length" class="space-y-2">
                  <h3 class="font-semibold">建议</h3>
                  <ul class="list-disc pl-5 text-sm text-gray-600 dark:text-gray-300">
                    <li v-for="item in reportContent.suggestions" :key="item">{{ item }}</li>
                  </ul>
                </div>
              </div>
            </div>
          </section>
        </div>
      </section>
    </div>
  </div>
</template>
