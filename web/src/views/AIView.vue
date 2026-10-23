<script setup lang="ts">
import { computed, onBeforeUnmount, onMounted, ref } from 'vue'
import { useRouter } from 'vue-router'
import { AlertCircle, Check, ChevronDown, Clock3, History, Info, Plus, RefreshCw, RotateCcw, ShieldCheck, SlidersHorizontal, Sparkles, Trash2 } from '@lucide/vue'
import FinancePage from '@/components/ui/FinancePage.vue'
import AppDialog from '@/components/ui/AppDialog.vue'
import ActionMenu from '@/components/ui/ActionMenu.vue'
import AIReportDocument from '@/components/ai/AIReportDocument.vue'
import AIGenerateDialog from '@/components/ai/AIGenerateDialog.vue'
import { aiApi, type AIProvider, type AIReport, type GenerateAIReportParams } from '@/api/ai'
import { parseReportContent, reportMatches, reportPeriod, retryParams, statusText, typeText } from '@/utils/aiReportPresentation'
import { createRequestGeneration } from '@/utils/requestGeneration'
import { toast } from '@/composables/useToast'
import '@/assets/ai-report.css'

const router = useRouter()
const loading = ref(true)
const providersReady = ref(false)
const reportsReady = ref(false)
const loadError = ref('')
const providers = ref<AIProvider[]>([])
const reports = ref<AIReport[]>([])
const selectedReport = ref<AIReport | null>(null)
const enabledProviders = computed(() => providers.value.filter(provider => provider.enabled))
const displayReport = computed(() => selectedReport.value?.status === 'completed' ? selectedReport.value : reports.value.find(report => report.status === 'completed') || null)
const showGenerate = ref(false)
const showHistory = ref(false)
const dialogTrigger = ref<HTMLElement | null>(null)
const contentRegion = ref<HTMLElement | null>(null)
const initialRequest = ref<GenerateAIReportParams | null>(null)
const deleting = ref(false)
const deleteTarget = ref<AIReport | null>(null)
const deleteError = ref('')
const generating = ref(false)
const requests = createRequestGeneration()
let disposed = false

type Attempt = { params: GenerateAIReportParams; beforeIds: string[]; status: 'running' | 'unknown' | 'failed'; message: string; checked: boolean; id?: string }
const attempt = ref<Attempt | null>(null)
const activeReport = computed(() => reports.value.find(report => report.status === 'pending' || report.status === 'running'))
const notice = computed(() => {
  if (attempt.value && (attempt.value.status !== 'failed' || !activeReport.value)) return attempt.value
  const report = activeReport.value || selectedReport.value
  if (!report || report.status === 'completed') return null
  return { status: report.status === 'failed' ? 'failed' : 'running', params: retryParams(report),
    message: report.error_message || '', checked: true, id: report.id } as Attempt
})
const stateConfirmed = computed(() => providersReady.value && reportsReady.value && !loading.value && !loadError.value)
const canRequest = computed(() => stateConfirmed.value && !generating.value && !activeReport.value && notice.value?.status !== 'running' && enabledProviders.value.length > 0)
const canStart = computed(() => canRequest.value && notice.value?.status !== 'unknown')
const failureTitle = computed(() => notice.value?.status === 'unknown' ? '生成结果尚未确认' : notice.value?.status === 'running' ? '正在分析你的账本' : '这次分析没有完成')
const failureBody = computed(() => notice.value?.status === 'unknown'
  ? '请求未能确认完成。请先检查报告状态，不会自动重复调用模型。'
  : notice.value?.status === 'running' ? '完整报告准备好后会在这里显示。离开页面不会取消服务端处理。'
  : '服务未能完成本次分析，未生成可用报告。上次完成的报告仍可查看。')

onMounted(loadData)
onBeforeUnmount(() => { disposed = true; requests.begin() })

function reconcileAttempt(list: AIReport[]) {
  const current = attempt.value
  if (!current || generating.value) return
  // Without a server request ID, only a single new record matching the complete
  // request can resolve a lost response. Older reports are not proof of success.
  const matches = list.filter(report => (current.id ? report.id === current.id : !current.beforeIds.includes(report.id)) && reportMatches(report, current.params))
  current.checked = true
  if (matches.length !== 1) return
  const result = matches[0]!
  current.id = result.id
  if (result.status === 'completed' && parseReportContent(result.content_json)) {
    selectedReport.value = result
    attempt.value = null
  } else if (result.status === 'failed') {
    current.status = 'failed'
    current.message = result.error_message || 'AI 服务未返回完整内容。'
  } else if (result.status === 'pending' || result.status === 'running') {
    current.status = 'running'
  }
}

async function loadData(preferredId?: string, confirmedReport?: AIReport) {
  const generation = requests.begin()
  loading.value = true
  loadError.value = ''
  const [providerResult, reportResult] = await Promise.allSettled([aiApi.listProviders(), aiApi.listReports()])
  if (disposed || !requests.isLatest(generation)) return
  if (providerResult.status === 'fulfilled') { providers.value = providerResult.value; providersReady.value = true }
  if (reportResult.status === 'fulfilled') {
    reports.value = reportResult.value
    // A successful POST response is authoritative even when the immediate list
    // read has not caught up. Later explicit refreshes use the server list alone.
    if (confirmedReport) reports.value = [confirmedReport, ...reports.value.filter(report => report.id !== confirmedReport.id)]
    reportsReady.value = true
    const selectionId = preferredId || selectedReport.value?.id
    selectedReport.value = reports.value.find(report => report.id === selectionId) || reports.value[0] || null
    reconcileAttempt(reports.value)
  }
  if (providerResult.status === 'rejected' || reportResult.status === 'rejected') {
    loadError.value = 'AI 数据加载失败，当前显示的内容可能不是最新状态。'
  }
  loading.value = false
}

function rememberTrigger(event?: Event) { dialogTrigger.value = event?.currentTarget instanceof HTMLElement ? event.currentTarget : null }
function openGenerate(retry = false, event?: Event) {
  if (!canRequest.value) return
  if (retry && notice.value) initialRequest.value = { ...notice.value.params }
  else { if (!canStart.value) return; initialRequest.value = null }
  rememberTrigger(event)
  showGenerate.value = true
}

async function generateReport(params: GenerateAIReportParams) {
  if (!canRequest.value) return
  if (!enabledProviders.value.some(provider => provider.id === params.provider_id)) return
  showGenerate.value = false
  generating.value = true
  const current: Attempt = { params: { ...params }, beforeIds: reports.value.map(report => report.id), status: 'running', message: '', checked: false }
  attempt.value = current
  let confirmedReport: AIReport | undefined
  try {
    const report = await aiApi.generateReport({ ...params })
    if (disposed) return
    confirmedReport = report
    reports.value = [report, ...reports.value.filter(item => item.id !== report.id)]
    if (report.status === 'completed' && parseReportContent(report.content_json)) {
      selectedReport.value = report
      attempt.value = null
      toast.success('AI 报告已生成')
    } else {
      current.id = report.id
      attempt.value = { ...current, status: report.status === 'pending' || report.status === 'running' ? 'running' : 'failed', message: report.error_message || '服务未返回可读取的完整报告。' }
    }
  } catch (error: unknown) {
    if (disposed) return
    attempt.value = { ...current, status: 'unknown', message: error instanceof Error ? error.message : '请求未完成' }
  } finally {
    if (!disposed) { generating.value = false; await loadData(selectedReport.value?.id, confirmedReport) }
  }
}

function selectHistory(report: AIReport) {
  selectedReport.value = report
  // A pending local request must not be hidden by changing the viewed report.
  if (attempt.value?.status === 'failed') attempt.value = null
  showHistory.value = false
}

function requestDelete(report: AIReport) {
  if (generating.value || report.status === 'running' || report.status === 'pending') return
  deleteTarget.value = report
  deleteError.value = ''
}
async function deleteReport() {
  if (!deleteTarget.value || deleting.value) return
  deleting.value = true
  const id = deleteTarget.value.id
  try {
    await aiApi.deleteReport(id)
    if (disposed) return
    reports.value = reports.value.filter(report => report.id !== id)
    if (selectedReport.value?.id === id) selectedReport.value = null
    if (attempt.value?.id === id) attempt.value = null
    deleteTarget.value = null
    await loadData()
    toast.success('报告已删除，账本不受影响')
  } catch {
    if (!disposed) deleteError.value = '删除未确认，请刷新报告列表核对后再试。'
  } finally { if (!disposed) deleting.value = false }
}
</script>

<template>
  <FinancePage title="AI 分析" :icon="Sparkles" class="ai-page">
    <template #actions>
      <button v-if="reports.length || generating" type="button" class="finance-button is-primary" :disabled="!canStart" @click="openGenerate(false, $event)"><Plus :size="17" />新建分析</button>
      <button type="button" aria-label="AI 设置" title="AI 设置" class="finance-icon-button" @click="router.push('/ai/settings')"><SlidersHorizontal :size="19" /></button>
    </template>
    <div ref="contentRegion" role="region" tabindex="-1" aria-label="AI 分析报告" class="ai-content-region">
    <div v-if="loadError" role="alert" class="ai-read-error"><span>{{ loadError }}</span><button type="button" class="finance-button is-subtle" @click="loadData()">重试加载</button></div>
    <div v-if="loading && !reportsReady" role="status" class="ai-loading"><RefreshCw :size="20" class="ai-spinner" />正在读取报告…</div>
    <section v-if="notice" :role="notice.status === 'running' ? 'status' : 'alert'" class="ai-notice" :class="{ 'is-running': notice.status === 'running' }">
      <RefreshCw v-if="notice.status === 'running'" :size="20" class="ai-spinner" /><AlertCircle v-else :size="20" />
      <div><h2>{{ failureTitle }}</h2><p>{{ typeText(notice.params.report_type) }} · {{ reportPeriod(notice.params) }}</p><p>{{ failureBody }}</p>
        <div class="ai-notice-actions"><button v-if="notice.status === 'failed'" type="button" class="finance-button is-subtle" :disabled="!canRequest" @click="openGenerate(true, $event)"><RotateCcw :size="16" />重新尝试</button><button v-else type="button" class="finance-button is-subtle" :disabled="loading || generating" @click="loadData()"><RefreshCw :size="16" />检查报告状态</button><button v-if="notice.status === 'unknown' && notice.checked" type="button" class="finance-button ai-text-button" :disabled="!canRequest" @click="openGenerate(true, $event)">重新确认生成</button></div>
        <details v-if="notice.message" class="ai-disclosure"><summary>查看详情<ChevronDown :size="15" /></summary><p>{{ notice.message }}</p></details>
      </div>
    </section>
    <template v-if="reportsReady && (reports.length || displayReport)">
      <div class="ai-toolbar"><div class="ai-report-period"><strong>{{ displayReport ? `${notice ? '上次完成 · ' : ''}${typeText(displayReport.report_type)}` : '报告记录' }}</strong><span v-if="displayReport">{{ reportPeriod(displayReport) }}</span></div><div class="ai-toolbar-actions"><button type="button" class="finance-button ai-text-button" @click="rememberTrigger($event); showHistory = true"><History :size="16" />历史报告</button><ActionMenu label="报告操作" :actions="[{ id: 'refresh', label: '刷新报告', icon: RefreshCw }, ...(displayReport ? [{ id: 'retry', label: '以此周期新建', icon: Plus }, { id: 'delete', label: '删除此报告', icon: Trash2, danger: true }] : [])]" @action="action => { if (action === 'refresh') loadData(); else if (action === 'delete' && displayReport) requestDelete(displayReport); else if (action === 'retry' && displayReport && canStart) { initialRequest = retryParams(displayReport); showGenerate = true } }" /></div></div>
      <AIReportDocument v-if="displayReport" :key="displayReport.id" :report="displayReport" />
      <p v-else class="ai-empty-history">还没有已完成的报告，生成记录可在历史报告中查看。</p>
      <p class="ai-page-note"><Info :size="13" />AI 解读仅供参考，不会自动记账或调整预算。</p>
    </template>
    <section v-else-if="reportsReady && providersReady && !loadError && !notice" class="ai-welcome">
      <span class="ai-welcome-icon"><Sparkles :size="29" /></span>
      <h2>{{ enabledProviders.length ? '开始第一份财务分析' : providers.length ? '选择一个可用的 AI 服务' : '让账本，多一份解读' }}</h2>
      <p>{{ enabledProviders.length ? '选择一个周期，看看收支、预算和需要留意的变化。' : providers.length ? '已保存的服务目前均已停用，请在 AI 设置中启用或添加服务。' : '连接你选择的 AI 服务，了解收支变化，发现需要留意的支出。' }}</p>
      <button v-if="enabledProviders.length" type="button" class="finance-button is-primary" :disabled="!canStart" @click="openGenerate(false, $event)"><Plus :size="17" />新建分析</button>
      <button v-else type="button" class="finance-button is-primary" @click="router.push('/ai/settings')">{{ providers.length ? '管理 AI 服务' : '连接 AI 服务' }}</button>
      <div class="ai-welcome-foot"><ShieldCheck :size="16" />由你发起分析，不会自动修改账本</div>
    </section>
    <p v-if="reportsReady && !reports.length && !loadError" class="ai-setup-note">生成时会发送财务汇总，不发送交易备注或附件。成员与账户名称默认替换。</p>
    <AIGenerateDialog :return-focus="dialogTrigger" :fallback-focus="contentRegion" v-if="showGenerate" :providers="providers" :initial="initialRequest" :uncertain="notice?.status === 'unknown'" @close="showGenerate = false" @generate="generateReport" />
    <AppDialog v-if="showHistory" title="历史报告" :return-focus="dialogTrigger" :fallback-focus="contentRegion" sheet @close="showHistory = false">
      <div class="ai-history"><button v-for="report in reports" :key="report.id" type="button" :aria-pressed="selectedReport?.id === report.id" class="ai-history-row" @click="selectHistory(report)"><Clock3 :size="20" /><span><strong>{{ typeText(report.report_type) }}</strong><span>{{ reportPeriod(report) }}</span><small>{{ statusText(report.status) }} · {{ report.provider_name }} · {{ report.model }}</small></span><Check v-if="selectedReport?.id === report.id" :size="17" /></button></div>
    </AppDialog>
    <AppDialog v-if="deleteTarget" title="删除报告" :fallback-focus="contentRegion" :busy="deleting" @close="deleteTarget = null"><p class="ai-prose">删除 {{ reportPeriod(deleteTarget) }} 的{{ typeText(deleteTarget.report_type) }}？账本数据不会改变。</p><p v-if="deleteError" role="alert" class="finance-form-error">{{ deleteError }}</p><template #footer><button class="finance-button is-subtle" :disabled="deleting" @click="deleteTarget = null">取消</button><button class="finance-button is-danger" :disabled="deleting" @click="deleteReport">{{ deleting ? '删除中…' : '确认删除' }}</button></template></AppDialog>
    </div>
  </FinancePage>
</template>
