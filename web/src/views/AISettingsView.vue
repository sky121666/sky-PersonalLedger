<script setup lang="ts">
import { computed, nextTick, onBeforeUnmount, onMounted, reactive, ref } from 'vue'
import { onBeforeRouteLeave, useRouter } from 'vue-router'
import { Cable, Pencil, Plus, RefreshCw, Trash2 } from '@lucide/vue'
import FinancePage from '@/components/ui/FinancePage.vue'
import AppDialog from '@/components/ui/AppDialog.vue'
import { aiApi, type AIProvider, type AIProviderPreset, type AIReportScheduleSettings, type SaveAIProviderParams } from '@/api/ai'
import { createRequestGeneration } from '@/utils/requestGeneration'
import { useAuthStore } from '@/stores/auth'

const router = useRouter()
const auth = useAuthStore()
const providers = ref<AIProvider[] | null>(null)
const providersLoading = ref(false)
const loadError = ref('')
const presets = ref<AIProviderPreset[]>([])
const presetsLoading = ref(false)
const presetsError = ref('')
const schedule = ref<AIReportScheduleSettings | null>(null)
const scheduleLoading = ref(false)
const scheduleError = ref('')
const providerRequests = createRequestGeneration()
const presetRequests = createRequestGeneration()
const scheduleRequests = createRequestGeneration()
let alive = true

const editorOpen = ref(false)
const editingProviderId = ref<string | null>(null)
const selectedPresetId = ref('')
const form = reactive({ name: '', provider_type: 'openai_compatible', base_url: '', model: '', api_key: '', enabled: true })
const baseline = ref('')
const formError = ref('')
const urlInvalid = ref(false)
const notice = ref('')
const navigationError = ref('')
const awaitingReadback = ref(false)
const createResultUncertain = ref(false)
const operation = ref<'save' | 'test' | 'toggle' | 'delete' | null>(null)
const busy = computed(() => operation.value !== null)
const rowFeedback = ref<Record<string, { kind: 'success' | 'error' | 'pending'; message: string }>>({})
const deleteTarget = ref<AIProvider | null>(null)
const deleteError = ref('')
const discardOpen = ref(false)
let discardResolver: ((discard: boolean) => void) | null = null
const editorHeading = ref<HTMLElement | null>(null)
const listHeading = ref<HTMLElement | null>(null)

function publicFields(value: typeof form | AIProvider): SaveAIProviderParams {
  return { name: value.name, provider_type: value.provider_type, base_url: value.base_url, model: value.model, enabled: value.enabled }
}
const dirty = computed(() => editorOpen.value && (form.api_key !== '' || JSON.stringify(publicFields(form)) !== baseline.value))
const modelSuggestions = computed(() => presets.value.find(item => item.id === selectedPresetId.value)?.models || [])
const scheduleStatus = computed(() => {
  if (scheduleLoading.value) return '读取中'
  if (scheduleError.value || !schedule.value) return '状态未知'
  return schedule.value.enabled ? '已开启' : '已关闭'
})
const scheduleSummary = computed(() => {
  if (scheduleLoading.value || scheduleError.value || !schedule.value) return ''
  if (!schedule.value.enabled) return '系统当前未开启自动报告。手动分析仍可在报告页发起。'
  const periods = [schedule.value.weekly_enabled ? '每周总结' : '', schedule.value.monthly_enabled ? '月度总结' : ''].filter(Boolean)
  const hour = String(schedule.value.hour).padStart(2, '0')
  return periods.length
    ? `已开启周期：${periods.join('、')}。系统检查小时：${hour}:00（服务器时间）。`
    : `系统总开关已开启，但未启用任何报告周期。检查小时：${hour}:00（服务器时间）。`
})

async function loadProviders() {
  if (!alive) return false
  const generation = providerRequests.begin()
  providersLoading.value = true
  loadError.value = ''
  try {
    const data = await aiApi.listProviders()
    if (!alive || !providerRequests.isLatest(generation)) return false
    if (!Array.isArray(data) || data.some(item => !item || typeof item.id !== 'string' || !item.id ||
      typeof item.name !== 'string' || typeof item.base_url !== 'string' || typeof item.model !== 'string' ||
      typeof item.provider_type !== 'string' || typeof item.enabled !== 'boolean')) throw new Error('Invalid providers')
    // Copy only public fields, even if a server response unexpectedly includes a key.
    providers.value = data.map(item => ({ ...publicFields(item), provider_type: item.provider_type,
      id: item.id, created_at: item.created_at, updated_at: item.updated_at }))
    return true
  } catch {
    if (alive && providerRequests.isLatest(generation)) loadError.value = '服务列表读取失败，当前状态未确认。请重试后再操作。'
    return false
  } finally {
    if (alive && providerRequests.isLatest(generation)) providersLoading.value = false
  }
}

async function loadPresets() {
  if (!alive) return
  const generation = presetRequests.begin()
  presetsLoading.value = true
  presetsError.value = ''
  try {
    const data = await aiApi.listProviderPresets()
    if (!alive || !presetRequests.isLatest(generation)) return
    if (!Array.isArray(data)) throw new Error('Invalid presets')
    presets.value = data
  } catch {
    if (alive && presetRequests.isLatest(generation)) presetsError.value = '预设读取失败，可以手动填写连接信息。'
  } finally {
    if (alive && presetRequests.isLatest(generation)) presetsLoading.value = false
  }
}

async function loadSchedule() {
  if (!alive) return
  const generation = scheduleRequests.begin()
  scheduleLoading.value = true
  scheduleError.value = ''
  try {
    const data = await aiApi.getScheduleSettings()
    if (!alive || !scheduleRequests.isLatest(generation)) return
    if (!data || typeof data.enabled !== 'boolean' || typeof data.weekly_enabled !== 'boolean' ||
      typeof data.monthly_enabled !== 'boolean' || !Number.isInteger(data.hour) || data.hour < 0 || data.hour > 23) {
      throw new Error('Invalid schedule')
    }
    schedule.value = data
  } catch {
    if (alive && scheduleRequests.isLatest(generation)) scheduleError.value = '系统自动报告状态读取失败，无法确认是否开启。'
  } finally {
    if (alive && scheduleRequests.isLatest(generation)) scheduleLoading.value = false
  }
}

async function loadData() { await Promise.all([loadProviders(), loadPresets(), loadSchedule()]) }

function canLeaveEditor(): boolean | Promise<boolean> {
  if (!alive) return false
  if (busy.value) { navigationError.value = '操作尚未完成，请等待结果后再离开。'; return false }
  if (!dirty.value) return true
  if (discardResolver) return false
  discardOpen.value = true
  return new Promise(resolve => { discardResolver = resolve })
}

function resolveDiscard(discard: boolean) {
  const resolve = discardResolver
  discardResolver = null
  discardOpen.value = false
  resolve?.(discard)
}

function beforeUnload(event: BeforeUnloadEvent) {
  if (!dirty.value && !busy.value) return
  event.preventDefault()
  event.returnValue = ''
}

function resetEditor(provider?: AIProvider) {
  editingProviderId.value = provider?.id || null
  Object.assign(form, provider ? publicFields(provider) : {
    name: '', provider_type: 'openai_compatible', base_url: '', model: '', enabled: true,
  }, { api_key: '' })
  selectedPresetId.value = ''
  baseline.value = JSON.stringify(publicFields(form))
  formError.value = ''
  urlInvalid.value = false
  awaitingReadback.value = false
  createResultUncertain.value = false
  notice.value = ''
  navigationError.value = ''
}

async function focusHeading(target: typeof editorHeading) {
  await nextTick()
  if (alive) target.value?.focus({ preventScroll: true })
}

async function startCreate() {
  if (providers.value === null || loadError.value || providersLoading.value || deleteTarget.value) return
  if (!await canLeaveEditor() || !alive || busy.value) return
  resetEditor()
  editorOpen.value = true
  void focusHeading(editorHeading)
}

async function editProvider(provider: AIProvider) {
  if (loadError.value || providersLoading.value || deleteTarget.value) return
  if (!await canLeaveEditor() || !alive || busy.value) return
  resetEditor(provider)
  editorOpen.value = true
  void focusHeading(editorHeading)
}

async function cancelEdit() {
  if (!await canLeaveEditor() || !alive || busy.value) return
  resetEditor()
  editorOpen.value = false
  void focusHeading(listHeading)
}

async function reviewCreateResult() {
  await cancelEdit()
  if (alive && !editorOpen.value) await loadProviders()
}

function applyPreset() {
  if (busy.value || awaitingReadback.value || createResultUncertain.value) return
  const preset = presets.value.find(item => item.id === selectedPresetId.value)
  if (!preset) return
  Object.assign(form, { name: preset.name, provider_type: preset.provider_type, base_url: preset.base_url, model: preset.model })
  urlInvalid.value = false
  formError.value = ''
}

function validBaseURL(value: string) {
  if (!/^https?:\/\/[^/]/i.test(value) || /[\s\\?#]/.test(value)) return false
  try {
    const url = new URL(value)
    return ['http:', 'https:'].includes(url.protocol) && !!url.hostname && !url.username && !url.password &&
      !url.search && !url.hash && !value.slice(value.indexOf('://') + 3).split('/')[0]?.includes('@')
  } catch { return false }
}

async function finishSaveReadback() {
  const loaded = await loadProviders()
  if (!alive) return
  const saved = loaded && providers.value?.find(item => item.id === editingProviderId.value)
  if (!saved) {
    formError.value = '配置已保存，但列表回读未确认。请重新读取配置，无需重复保存。'
    return
  }
  awaitingReadback.value = false
  resetEditor()
  editorOpen.value = false
  notice.value = '配置已保存。测试连接需单独点击，不会自动发送测试请求。'
  void focusHeading(listHeading)
}

async function saveProvider() {
  if (!alive || busy.value || !editorOpen.value || awaitingReadback.value || createResultUncertain.value) return
  formError.value = ''
  notice.value = ''
  urlInvalid.value = false
  if (!form.name.trim() || !form.base_url.trim() || !form.model.trim()) {
    formError.value = '请填写显示名称、模型和接口地址。'
    return
  }
  if (!validBaseURL(form.base_url.trim())) {
    urlInvalid.value = true
    formError.value = '接口地址需为完整的 http 或 https URL，不能包含用户名、密码、查询参数或片段。'
    return
  }
  operation.value = 'save'
  if (editingProviderId.value) delete rowFeedback.value[editingProviderId.value]
  try {
    const params: SaveAIProviderParams = { ...publicFields(form), name: form.name.trim(),
      base_url: form.base_url.trim(), model: form.model.trim() }
    if (form.api_key.trim()) params.api_key = form.api_key.trim()
    const saved = editingProviderId.value
      ? await aiApi.updateProvider(editingProviderId.value, params)
      : await aiApi.createProvider(params)
    if (!alive) return
    if (!saved || typeof saved.id !== 'string' || !saved.id) throw new Error('Missing saved identity')
    editingProviderId.value = saved.id
    form.api_key = ''
    baseline.value = JSON.stringify(publicFields(form))
    awaitingReadback.value = true
    await finishSaveReadback()
  } catch (error: unknown) {
    if (!alive) return
    const status = (error as { status?: number } | null)?.status
    const message = (error as { message?: unknown } | null)?.message
    // Without a confirmed rejection, retrying POST could create the service twice.
    if (!editingProviderId.value && (!status || status >= 500 || status === 408)) {
      createResultUncertain.value = true
      formError.value = '新增结果未确认，填写内容已保留。为避免重复创建，请返回并核对服务列表；若已存在，请编辑该服务。'
    } else if (status === 400 && message === 'ai provider base url is invalid') {
      urlInvalid.value = true
      formError.value = '服务器拒绝此接口地址，填写内容已保留。本机或内网服务需由服务器允许相应的出站访问，请检查地址和服务器设置后重试。'
    } else {
      formError.value = '保存失败，填写内容已保留。请检查连接信息后重试。'
    }
  } finally {
    if (alive) { operation.value = null; navigationError.value = '' }
  }
}

async function retrySavedRead() {
  if (!alive || busy.value || !awaitingReadback.value) return
  operation.value = 'save'
  await finishSaveReadback()
  if (alive) { operation.value = null; navigationError.value = '' }
}

function rowActionAllowed() {
  return alive && !busy.value && !editorOpen.value && !providersLoading.value && !loadError.value && !deleteTarget.value
}

async function testProvider(provider: AIProvider) {
  if (editorOpen.value) {
    if (!busy.value) formError.value = '请先保存当前配置，再回到列表测试连接。测试使用的是已保存的版本。'
    return
  }
  if (!rowActionAllowed()) return
  operation.value = 'test'
  rowFeedback.value[provider.id] = { kind: 'pending', message: '正在测试连接…' }
  try {
    const result = await aiApi.testProvider(provider.id)
    if (!alive) return
    rowFeedback.value[provider.id] = result.ok === true
      ? { kind: 'success', message: '连接测试通过。' }
      : { kind: 'error', message: '连接测试未通过，请检查服务配置后重试。' }
  } catch {
    if (alive) rowFeedback.value[provider.id] = { kind: 'error', message: '连接测试失败，请检查服务配置或网络后重试。' }
  } finally {
    if (alive) { operation.value = null; navigationError.value = '' }
  }
}

async function toggleProvider(provider: AIProvider) {
  if (!rowActionAllowed()) return
  operation.value = 'toggle'
  rowFeedback.value[provider.id] = { kind: 'pending', message: '正在更新状态…' }
  try {
    await aiApi.updateProvider(provider.id, { ...publicFields(provider), enabled: !provider.enabled })
    if (!alive) return
    const loaded = await loadProviders()
    if (!alive) return
    rowFeedback.value[provider.id] = loaded
      ? { kind: 'success', message: '服务状态已更新。' }
      : { kind: 'error', message: '状态已保存，但列表读取失败，请刷新确认。' }
  } catch {
    if (alive) rowFeedback.value[provider.id] = { kind: 'error', message: '服务状态更新失败，请刷新确认后重试。' }
  } finally {
    if (alive) { operation.value = null; navigationError.value = '' }
  }
}

function askDelete(provider: AIProvider) {
  if (!rowActionAllowed()) return
  deleteTarget.value = provider
  deleteError.value = ''
}
function closeDelete() { if (!busy.value) { deleteTarget.value = null; deleteError.value = '' } }
async function confirmDelete() {
  if (!alive || busy.value || !deleteTarget.value) return
  operation.value = 'delete'
  deleteError.value = ''
  try {
    await aiApi.deleteProvider(deleteTarget.value.id)
    if (!alive) return
    deleteTarget.value = null
    notice.value = ''
    const loaded = await loadProviders()
    if (alive && loaded) notice.value = '服务配置已删除。'
  } catch {
    if (alive) deleteError.value = '删除失败，当前结果未确认。请关闭弹窗并刷新列表后再决定是否重试。'
  } finally {
    if (alive) { operation.value = null; navigationError.value = '' }
  }
}

function goBack() { void router.push('/ai') }
onBeforeRouteLeave(() => {
  // Preserve the existing auth redirect, including expiry during an API request.
  if (!auth.isLoggedIn) { resolveDiscard(false); return true }
  return canLeaveEditor()
})
onMounted(() => { window.addEventListener('beforeunload', beforeUnload); void loadData() })
onBeforeUnmount(() => {
  alive = false
  providerRequests.begin()
  presetRequests.begin()
  scheduleRequests.begin()
  form.api_key = ''
  resolveDiscard(false)
  window.removeEventListener('beforeunload', beforeUnload)
})
</script>

<template>
  <FinancePage title="AI 设置" back-label="返回 AI 分析" @back="goBack">
    <p v-if="notice" class="ai-settings-success" role="status">{{ notice }}</p>
    <p v-if="navigationError" class="finance-form-error" role="alert">{{ navigationError }}</p>

    <section class="finance-card ai-settings-panel" aria-labelledby="ai-services-title">
      <template v-if="!editorOpen">
        <header class="ai-settings-section-head">
          <div>
            <h2 id="ai-services-title" ref="listHeading" tabindex="-1">AI 服务</h2>
            <p class="finance-muted">管理连接信息，报告页专注分析。</p>
          </div>
          <button type="button" class="finance-button is-primary" :disabled="busy || providersLoading || providers === null || !!loadError" @click="startCreate">
            <Plus :size="16" aria-hidden="true" />新增服务
          </button>
        </header>
        <div v-if="loadError" class="ai-settings-read-error" role="alert">
          <p>{{ loadError }}</p>
          <button type="button" class="finance-button is-subtle" :disabled="busy || providersLoading" @click="loadProviders">重新读取</button>
        </div>
        <p v-if="providersLoading" class="finance-muted" role="status">正在读取服务配置…</p>
        <div v-else-if="providers?.length === 0 && !loadError" class="finance-empty">
          <h3>尚未添加 AI 服务</h3>
          <p>添加后先保存，再按需测试连接。</p>
        </div>
        <ul v-if="providers?.length" class="ai-settings-providers" :aria-busy="providersLoading">
          <li v-for="provider in providers" :key="provider.id" class="ai-settings-provider">
            <div class="ai-settings-provider-info">
              <div class="ai-settings-provider-title"><h3>{{ provider.name }}</h3><span class="ai-settings-tag">{{ provider.enabled ? '已启用' : '已停用' }}</span></div>
              <p class="finance-muted">{{ provider.model }}</p>
              <p class="finance-muted ai-settings-url">{{ provider.base_url }}</p>
            </div>
            <div class="ai-settings-provider-actions">
              <button type="button" class="finance-button is-subtle" :disabled="busy || providersLoading || !!loadError" :aria-label="`编辑 ${provider.name}`" @click="editProvider(provider)"><Pencil :size="15" aria-hidden="true" />编辑</button>
              <button type="button" class="finance-button" :disabled="busy || providersLoading || !!loadError" :aria-label="`测试 ${provider.name} 的连接`" @click="testProvider(provider)"><Cable :size="15" aria-hidden="true" />测试连接</button>
              <button type="button" class="finance-button" :disabled="busy || providersLoading || !!loadError" :aria-label="`${provider.enabled ? '停用' : '启用'} ${provider.name}`" @click="toggleProvider(provider)">{{ provider.enabled ? '停用' : '启用' }}</button>
              <button type="button" class="finance-icon-button is-danger" :disabled="busy || providersLoading || !!loadError" :aria-label="`删除 ${provider.name}`" @click="askDelete(provider)"><Trash2 :size="16" aria-hidden="true" /></button>
            </div>
            <p v-if="rowFeedback[provider.id]" class="ai-settings-feedback" :class="`is-${rowFeedback[provider.id]!.kind}`" :role="rowFeedback[provider.id]!.kind === 'error' ? 'alert' : 'status'">{{ rowFeedback[provider.id]!.message }}</p>
          </li>
        </ul>
        <p class="finance-muted ai-settings-test-note">测试连接会向所选服务发送测试请求；保存配置不会自动测试。</p>
      </template>

      <form v-else novalidate :aria-busy="busy" @submit.prevent="saveProvider">
        <header class="ai-settings-section-head">
          <div><h2 id="ai-services-title" ref="editorHeading" tabindex="-1">{{ editingProviderId ? '编辑 AI 服务' : '新增 AI 服务' }}</h2><p class="finance-muted">兼容 OpenAI 接口的服务，可使用预设或手动填写。</p></div>
        </header>
        <fieldset class="finance-form-grid ai-settings-fields" :disabled="busy || awaitingReadback || createResultUncertain">
          <div class="finance-field ai-settings-full">
            <label for="ai-service-preset">服务预设</label>
            <select id="ai-service-preset" v-model="selectedPresetId" class="finance-input" :disabled="presetsLoading" @change="applyPreset">
              <option value="">自定义 / 保留当前配置</option><option v-for="preset in presets" :key="preset.id" :value="preset.id">{{ preset.name }}</option>
            </select>
            <span class="finance-muted">选择预设会填入名称、地址和模型，保留已输入的密钥与启停状态。</span>
            <p v-if="presetsError" class="finance-form-error" role="alert">{{ presetsError }} <button type="button" class="ai-settings-text-button" :disabled="presetsLoading" @click="loadPresets">重试</button></p>
          </div>
          <div class="finance-field"><label for="ai-service-name">显示名称</label><input id="ai-service-name" v-model="form.name" class="finance-input" required autocomplete="off" /></div>
          <div class="finance-field"><label for="ai-service-model">模型</label><input id="ai-service-model" v-model="form.model" class="finance-input" list="ai-service-models" required autocomplete="off" spellcheck="false" aria-describedby="ai-model-help" /><span id="ai-model-help" class="finance-muted">可自由输入服务支持的模型名称。</span><datalist id="ai-service-models"><option v-for="model in modelSuggestions" :key="model" :value="model" /></datalist></div>
          <div class="finance-field ai-settings-full"><label for="ai-service-url">接口地址</label><input id="ai-service-url" v-model="form.base_url" class="finance-input" type="url" required autocomplete="off" spellcheck="false" :aria-invalid="urlInvalid" aria-describedby="ai-url-help ai-form-error" /><span id="ai-url-help" class="finance-muted">使用 http 或 https 地址，不含用户名、密码、查询参数或片段。本地服务还需符合服务器的网络访问策略。</span></div>
          <div class="finance-field ai-settings-full"><label for="ai-service-key">API Key</label><input id="ai-service-key" v-model="form.api_key" class="finance-input" type="password" autocomplete="new-password" spellcheck="false" autocapitalize="none" aria-describedby="ai-key-help" /><span id="ai-key-help" class="finance-muted">{{ editingProviderId ? '留空保留已保存的密钥；现有密钥不会回显。' : '无需鉴权的本地服务可留空；其他服务请填写其密钥。' }} 保存成功后清空输入。</span></div>
          <label class="ai-settings-check ai-settings-full"><input v-model="form.enabled" type="checkbox" /><span>启用此服务<span class="finance-muted">停用后不参与报告生成，配置仍会保留。</span></span></label>
        </fieldset>
        <p v-if="formError" id="ai-form-error" class="finance-form-error" role="alert">{{ formError }}</p>
        <p class="finance-muted ai-settings-save-note">先保存，再回到列表显式测试连接。测试会使用已保存的配置。</p>
        <footer class="ai-settings-form-footer">
          <button type="button" class="finance-button is-subtle" :disabled="busy" @click="cancelEdit">{{ awaitingReadback ? '返回服务列表' : '取消' }}</button>
          <button v-if="awaitingReadback" type="button" class="finance-button is-primary" :disabled="busy" @click="retrySavedRead"><RefreshCw :size="16" aria-hidden="true" />{{ busy ? '读取中…' : '重新读取配置' }}</button>
          <button v-else-if="createResultUncertain" type="button" class="finance-button is-primary" :disabled="busy" @click="reviewCreateResult">核对服务列表</button>
          <button v-else type="submit" class="finance-button is-primary" :disabled="busy">{{ busy ? '保存中…' : '保存配置' }}</button>
        </footer>
      </form>
    </section>

    <section class="ai-settings-schedule" aria-labelledby="ai-schedule-title" :aria-busy="scheduleLoading">
      <div class="ai-settings-section-head"><div><h2 id="ai-schedule-title">自动报告</h2><p class="finance-muted">这是系统级任务，作用于系统内符合条件的用户。</p></div><span class="ai-settings-tag" role="status">{{ scheduleStatus }}</span></div>
      <div v-if="scheduleError" class="ai-settings-read-error" role="alert"><p>{{ scheduleError }}</p><button type="button" class="finance-button is-subtle" :disabled="scheduleLoading" @click="loadSchedule">重新读取状态</button></div>
      <p v-else-if="scheduleSummary" class="finance-muted">{{ scheduleSummary }}</p>
      <details class="ai-settings-disclosure"><summary>为什么这里没有个人开关？</summary><p class="finance-muted">当前调度并非个人偏好。这里仅展示系统状态，不会更改自动报告设置，也不会立即触发任务。</p></details>
    </section>

    <AppDialog v-if="discardOpen" title="放弃未保存的修改？" @close="resolveDiscard(false)">
      <p class="finance-muted">{{ createResultUncertain ? '上次新增可能已在服务器保存。离开会清空此处的输入，请在服务列表核对结果后再操作。' : '本次填写的连接信息和密钥尚未保存。离开后需要重新填写。' }}</p>
      <template #footer><button type="button" class="finance-button is-subtle" @click="resolveDiscard(false)">继续编辑</button><button type="button" class="finance-button is-danger" @click="resolveDiscard(true)">放弃修改</button></template>
    </AppDialog>
    <AppDialog v-if="deleteTarget" title="删除 AI 服务？" :busy="busy" :fallback-focus="listHeading" @close="closeDelete">
      <p class="ai-settings-delete-copy">确定删除「{{ deleteTarget.name }}」的连接配置？已生成的报告不会删除。</p>
      <p v-if="deleteError" class="finance-form-error" role="alert">{{ deleteError }}</p>
      <template #footer><button type="button" class="finance-button is-subtle" :disabled="busy" @click="closeDelete">取消</button><button type="button" class="finance-button is-danger" :disabled="busy" @click="confirmDelete">{{ busy ? '删除中…' : '确认删除' }}</button></template>
    </AppDialog>
  </FinancePage>
</template>

<style scoped>
.ai-settings-panel { padding: 26px 28px; border-color: var(--fp-line); }
.ai-settings-section-head { display: flex; align-items: flex-start; justify-content: space-between; gap: 16px; margin-bottom: 22px; }
.ai-settings-section-head h2 { margin: 0; font-size: 16px; font-weight: 600; }
.ai-settings-section-head p { margin-top: 7px; }
.ai-settings-section-head h2:focus { outline: none; }
.ai-settings-providers { padding: 0; margin: 0; list-style: none; }
.ai-settings-provider { padding: 20px 0; border-top: 1px solid var(--fp-line); }
.ai-settings-provider:first-child { padding-top: 0; border-top: 0; }
.ai-settings-provider-info { min-width: 0; }
.ai-settings-provider-title { display: flex; align-items: center; flex-wrap: wrap; gap: 10px; margin-bottom: 6px; }
.ai-settings-provider h3 { font-size: 14px; font-weight: 600; overflow-wrap: anywhere; }
.ai-settings-provider p { overflow-wrap: anywhere; }
.ai-settings-url { margin-top: 3px; }
.ai-settings-provider-actions { display: flex; flex-wrap: wrap; align-items: center; gap: 6px; margin-top: 14px; }
.ai-settings-provider-actions .is-danger { color: var(--fp-red); margin-left: auto; }
.ai-settings-tag { flex: none; border-radius: 7px; padding: 4px 8px; font-size: 11px; background: var(--fp-soft); color: var(--fp-secondary); white-space: nowrap; }
.ai-settings-fields { border: 0; padding: 0; margin: 0; min-width: 0; gap: 18px; }
.ai-settings-fields:disabled { opacity: .7; }
.ai-settings-full { grid-column: 1 / -1; }
.ai-settings-check { display: flex; align-items: flex-start; gap: 10px; font-size: 13px; }
.ai-settings-check input { width: 18px; height: 18px; flex: none; margin-top: 2px; accent-color: var(--fp-blue); }
.ai-settings-check .finance-muted { display: block; margin-top: 4px; }
.ai-settings-form-footer { display: flex; flex-wrap: wrap; justify-content: flex-end; gap: 12px; margin-top: 25px; padding-top: 20px; border-top: 1px solid var(--fp-line); }
.ai-settings-form-footer > :first-child { margin-right: auto; }
.ai-settings-test-note { padding-top: 16px; border-top: 1px solid var(--fp-line); }
.ai-settings-save-note { margin-top: 18px; }
.ai-settings-read-error { display: flex; flex-wrap: wrap; align-items: center; gap: 12px; color: var(--fp-red); font-size: 13px; line-height: 1.7; margin-bottom: 18px; }
.ai-settings-success,.ai-settings-feedback { font-size: 13px; line-height: 1.7; overflow-wrap: anywhere; }
.ai-settings-success,.ai-settings-feedback.is-success { color: var(--fp-green); }
.ai-settings-feedback { margin-top: 12px; color: var(--fp-secondary); }
.ai-settings-feedback.is-error { color: var(--fp-red); }
.ai-settings-text-button { min-height: 44px; color: var(--fp-blue); text-decoration: underline; padding: 0 8px; }
.ai-settings-schedule { padding: 6px 8px; }
.ai-settings-schedule .ai-settings-section-head { margin-bottom: 12px; }
.ai-settings-schedule h2 { font-size: 14px; }
.ai-settings-disclosure { margin-top: 14px; font-size: 12px; color: var(--fp-secondary); }
.ai-settings-disclosure summary { cursor: pointer; min-height: 44px; padding: 12px 0; }
.ai-settings-delete-copy { overflow-wrap: anywhere; font-size: 14px; line-height: 1.8; }
@media (max-width: 767px) {
  .ai-settings-panel { padding: 23px 20px; }
  .ai-settings-section-head { flex-wrap: wrap; gap: 12px; }
  .ai-settings-section-head h2 { font-size: 15px; }
  .ai-settings-fields .finance-input { font-size: 16px; }
  .ai-settings-provider-actions { gap: 4px; }
  .ai-settings-provider-actions .finance-button { padding: 0 10px; }
  .ai-settings-form-footer > .finance-button { flex: 1; }
  .ai-settings-schedule { padding: 6px 2px; }
}
</style>
