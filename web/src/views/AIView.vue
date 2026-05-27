<script setup lang="ts">
import { computed, onMounted, reactive, ref } from 'vue'
import { useRouter } from 'vue-router'
import { ArrowLeft, Bot, KeyRound, PlayCircle, RefreshCw, Trash2 } from 'lucide-vue-next'
import { aiApi, type AIProvider, type AIReport } from '@/api/ai'
import { toast } from '@/composables/useToast'

const router = useRouter()
const loading = ref(false)
const saving = ref(false)
const testingId = ref<string | null>(null)
const generating = ref(false)
const providers = ref<AIProvider[]>([])
const reports = ref<AIReport[]>([])
const selectedReport = ref<AIReport | null>(null)

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

const enabledProviders = computed(() => providers.value.filter(provider => provider.enabled))
const reportContent = computed(() => parseReportContent(selectedReport.value?.content_json))

onMounted(loadData)

async function loadData() {
  loading.value = true
  try {
    const [providerList, reportList] = await Promise.all([
      aiApi.listProviders(),
      aiApi.listReports()
    ])
    providers.value = providerList
    reports.value = reportList
    reportForm.provider_id ||= enabledProviders.value[0]?.id || ''
    selectedReport.value = reportList[0] || null
  } catch (error: any) {
    toast.error(error.message || 'AI 数据加载失败')
  } finally {
    loading.value = false
  }
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

function statusText(status: string) {
  return ({ completed: '已完成', running: '生成中', failed: '失败', pending: '待处理' } as Record<string, string>)[status] || status
}

function typeText(type: string) {
  return ({ weekly: '每周总结', monthly: '月度总结', family: '家庭分析', budget: '预算建议' } as Record<string, string>)[type] || '财务分析'
}

function shortDate(value: string) {
  return value?.slice(0, 10) || ''
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
            <input v-model="providerForm.name" autocomplete="off" class="w-full px-3 py-3 rounded-xl bg-gray-100 dark:bg-white/10 outline-none" placeholder="名称" />
            <input v-model="providerForm.base_url" autocomplete="url" class="w-full px-3 py-3 rounded-xl bg-gray-100 dark:bg-white/10 outline-none" placeholder="Base URL" />
            <input v-model="providerForm.model" autocomplete="off" class="w-full px-3 py-3 rounded-xl bg-gray-100 dark:bg-white/10 outline-none" placeholder="模型，例如 deepseek-chat" />
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
                <div v-if="reportContent?.highlights?.length" class="space-y-2">
                  <h3 class="font-semibold">重点</h3>
                  <ul class="list-disc pl-5 text-sm text-gray-600 dark:text-gray-300">
                    <li v-for="item in reportContent.highlights" :key="item">{{ item }}</li>
                  </ul>
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
