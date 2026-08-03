<script setup lang="ts">
import { computed, onMounted, reactive, ref, watch } from 'vue'
import { useRoute, useRouter } from 'vue-router'
import { useAuthStore } from '@/stores/auth'
import { setupApi, type SetupStatus } from '@/api/setup'
import {
  ArrowRight,
  CheckCircle2,
  ChevronDown,
  ChevronLeft,
  Database,
  Eye,
  EyeOff,
  Lock,
  RotateCw,
  Settings2,
  Wallet
} from 'lucide-vue-next'
import { toast } from '@/composables/useToast'
import { setSetupToken } from '@/utils/setupAccess'

type SetupStep = 'database' | 'password' | 'complete'

const router = useRouter()
const route = useRoute()
const authStore = useAuthStore()

const setupStatus = ref<SetupStatus | null>(null)
const loadingStatus = ref(true)
const currentStep = ref<SetupStep>('database')
const showDatabaseForm = ref(false)
const showAdvancedSettings = ref(false)
const databaseTesting = ref(false)
const databaseTested = ref(false)
const databaseSaving = ref(false)
const restartRequired = ref(false)
const savedConfigPath = ref('')
const password = ref('')
const confirmPassword = ref('')
const creatingPassword = ref(false)
const showPassword = ref(false)
const showConfirmPassword = ref(false)
const useAdvancedDsn = ref(false)

const setupSteps: Array<{ key: SetupStep; label: string }> = [
  { key: 'database', label: '数据库' },
  { key: 'password', label: '访问密码' },
  { key: 'complete', label: '完成' }
]

const databaseDrivers = [
  { value: 'sqlite', label: 'SQLite' },
  { value: 'postgres', label: 'PostgreSQL' },
  { value: 'mysql', label: 'MySQL' }
]

const defaultTimeZone = Intl.DateTimeFormat().resolvedOptions().timeZone || 'Local'

const databaseForm = reactive({
  driver: 'sqlite',
  path: '',
  dsn: '',
  host: '127.0.0.1',
  port: 3306,
  database: '',
  username: '',
  password: '',
  ssl_mode: 'disable',
  timezone: defaultTimeZone,
  max_open_conns: 0,
  max_idle_conns: 0
})

const usesSqlite = computed(() => databaseForm.driver === 'sqlite' || databaseForm.driver === 'sqlite3')
const usesPostgres = computed(() => databaseForm.driver === 'postgres' || databaseForm.driver === 'postgresql')
const currentStepIndex = computed(() => setupSteps.findIndex((step) => step.key === currentStep.value))
const canEditDatabase = computed(() => !databaseSaving.value && !restartRequired.value)

watch(databaseForm, () => {
  databaseTested.value = false
}, { deep: true })

onMounted(async () => {
  const routeSetupToken = Array.isArray(route.query.setup_token)
    ? route.query.setup_token[0]
    : route.query.setup_token
  if (setSetupToken(routeSetupToken)) {
    const nextQuery = { ...route.query }
    delete nextQuery.setup_token
    await router.replace({ path: route.path, query: nextQuery })
  }

  await authStore.checkAuth()
  if (authStore.initialized === true) {
    router.replace(authStore.isLoggedIn ? '/' : '/login')
    return
  }

  await loadSetupStatus()
})

async function loadSetupStatus() {
  loadingStatus.value = true
  try {
    setupStatus.value = await setupApi.getStatus()
    if (setupStatus.value.initialized) {
      router.replace(authStore.isLoggedIn ? '/' : '/login')
      return
    }
    resetDatabaseForm()
    currentStep.value = 'database'
  } catch (e: any) {
    toast.error(e.message || '读取初始化状态失败')
  } finally {
    loadingStatus.value = false
  }
}

async function testDatabaseConnection() {
  if (!setupStatus.value?.database) return false
  const validationMessage = validateDatabaseForm()
  if (validationMessage) {
    toast.warning(validationMessage)
    return false
  }
  databaseTesting.value = true
  databaseTested.value = false
  try {
    await setupApi.testDatabase(buildDatabaseRequest())
    databaseTested.value = true
    toast.success('数据库连接正常')
    return true
  } catch (e: any) {
    toast.error(e.message || '数据库连接测试失败')
    return false
  } finally {
    databaseTesting.value = false
  }
}

async function applyDatabaseConfig() {
  if (!setupStatus.value?.database) return
  const validationMessage = validateDatabaseForm()
  if (validationMessage) {
    toast.warning(validationMessage)
    return
  }
  databaseSaving.value = true
  databaseTested.value = false
  const request = buildDatabaseRequest()
  try {
    await setupApi.testDatabase(request)
    databaseTested.value = true
    const result = await setupApi.applyDatabase(request)
    restartRequired.value = result.restart_required
    savedConfigPath.value = result.config_path
    toast.success('数据库配置已保存')
  } catch (e: any) {
    toast.error(e.message || '测试或保存数据库配置失败')
  } finally {
    databaseSaving.value = false
  }
}

async function createAccessPassword() {
  if (password.value.length < 8) {
    toast.warning('密码至少需要 8 位')
    return
  }
  if (password.value !== confirmPassword.value) {
    toast.warning('两次输入的密码不一致')
    return
  }

  creatingPassword.value = true
  try {
    await authStore.init(password.value)
    toast.success('初始化成功')
    currentStep.value = 'complete'
  } catch (e: any) {
    toast.error(e.message || '初始化失败，请重试')
    password.value = ''
    confirmPassword.value = ''
  } finally {
    creatingPassword.value = false
  }
}

function resetDatabaseForm() {
  const db = setupStatus.value?.database
  if (!db) return
  databaseForm.driver = db.driver || 'sqlite'
  databaseForm.path = db.path || './data/ledger.db'
  databaseForm.dsn = ''
  databaseForm.host = '127.0.0.1'
  databaseForm.port = defaultDatabasePort(databaseForm.driver)
  databaseForm.database = ''
  databaseForm.username = ''
  databaseForm.password = ''
  databaseForm.ssl_mode = 'disable'
  databaseForm.timezone = defaultTimeZone
  databaseForm.max_open_conns = db.max_open_conns || 0
  databaseForm.max_idle_conns = db.max_idle_conns || 0
}

function buildDatabaseRequest() {
  const base = {
    driver: databaseForm.driver,
    max_open_conns: Number(databaseForm.max_open_conns) || 0,
    max_idle_conns: Number(databaseForm.max_idle_conns) || 0
  }
  if (usesSqlite.value) {
    return {
      ...base,
      path: databaseForm.path,
      dsn: ''
    }
  }
  if (useAdvancedDsn.value) {
    return {
      ...base,
      path: '',
      dsn: databaseForm.dsn
    }
  }
  return {
    ...base,
    path: '',
    dsn: '',
    host: databaseForm.host,
    port: Number(databaseForm.port) || 0,
    database: databaseForm.database,
    username: databaseForm.username,
    password: databaseForm.password,
    ssl_mode: usesPostgres.value ? databaseForm.ssl_mode : '',
    timezone: databaseForm.timezone
  }
}

function validateDatabaseForm() {
  if (Number(databaseForm.max_open_conns) < 0 || Number(databaseForm.max_idle_conns) < 0) {
    return '连接池数量不能小于 0'
  }
  if (usesSqlite.value) {
    return databaseForm.path.trim() ? '' : '请输入 SQLite 数据库路径'
  }
  if (useAdvancedDsn.value) {
    return databaseForm.dsn.trim() ? '' : '请输入数据库 DSN'
  }
  if (!databaseForm.host.trim()) return '请输入数据库主机'
  if (!Number(databaseForm.port)) return '请输入数据库端口'
  if (!databaseForm.database.trim()) return '请输入数据库名称'
  if (!databaseForm.username.trim()) return '请输入数据库用户名'
  return ''
}

function setDatabaseDriver(driver: string) {
  databaseForm.driver = driver
  databaseForm.port = defaultDatabasePort(driver)
  databaseForm.ssl_mode = driver === 'postgres' ? 'disable' : ''
  databaseForm.timezone = defaultTimeZone
  useAdvancedDsn.value = false
  databaseTested.value = false
}

function defaultDatabasePort(driver: string) {
  if (driver === 'postgres' || driver === 'postgresql') return 5432
  if (driver === 'mysql' || driver === 'mariadb') return 3306
  return 0
}

function databaseLabel() {
  const driver = databaseForm.driver || setupStatus.value?.database?.driver || 'sqlite'
  const names: Record<string, string> = {
    sqlite: 'SQLite',
    sqlite3: 'SQLite',
    postgres: 'PostgreSQL',
    postgresql: 'PostgreSQL',
    mysql: 'MySQL',
    mariadb: 'MariaDB'
  }
  return names[driver] || driver
}

function databaseSummary() {
  if (usesSqlite.value) {
    return databaseForm.path || './data/ledger.db'
  }
  if (databaseForm.dsn.trim()) {
    return 'DSN 已填写'
  }
  if (useAdvancedDsn.value) {
    return setupStatus.value?.database?.dsn_configured ? 'DSN 已配置' : 'DSN 未填写'
  }
  if (setupStatus.value?.database?.dsn_configured) {
    return 'DSN 已配置'
  }
  const host = databaseForm.host || '127.0.0.1'
  const port = databaseForm.port || defaultDatabasePort(databaseForm.driver)
  const name = databaseForm.database || '未填写库名'
  return `${host}:${port}/${name}`
}

function revealDatabaseForm() {
  showDatabaseForm.value = true
}

function revealAdvancedSettings() {
  showDatabaseForm.value = true
  showAdvancedSettings.value = true
}

function cancelDatabaseChange() {
  resetDatabaseForm()
  showDatabaseForm.value = false
  showAdvancedSettings.value = false
  useAdvancedDsn.value = false
  databaseTested.value = false
}

function toggleAdvancedSettings() {
  showAdvancedSettings.value = !showAdvancedSettings.value
  if (!showAdvancedSettings.value) {
    useAdvancedDsn.value = false
  }
}

function continueWithCurrentDatabase() {
  if (restartRequired.value) return
  currentStep.value = 'password'
}

function backToDatabaseStep() {
  currentStep.value = 'database'
}

function enterLedger() {
  router.replace('/')
}
</script>

<template>
  <div class="min-h-dvh bg-gray-50 px-4 py-8 dark:bg-gray-900 sm:py-10">
    <main class="mx-auto w-full max-w-[720px]">
      <header class="mb-6 text-center">
        <div class="mx-auto mb-4 flex h-12 w-12 items-center justify-center rounded-xl bg-primary text-white shadow-sm shadow-primary/20">
          <Wallet :size="26" />
        </div>
        <h1 class="text-2xl font-bold text-gray-950 dark:text-white">Personal Ledger 初始化</h1>
        <p class="mt-2 text-sm text-gray-500 dark:text-gray-400">按步骤完成数据库和访问密码设置。</p>
      </header>

      <nav aria-label="初始化步骤" class="mb-5 rounded-2xl border border-gray-200 bg-white p-3 dark:border-gray-700 dark:bg-gray-800">
        <ol class="grid grid-cols-3 gap-2">
          <li v-for="(step, index) in setupSteps" :key="step.key" class="flex items-center gap-2">
            <div
              class="flex h-8 w-8 shrink-0 items-center justify-center rounded-full text-xs font-bold"
              :class="index <= currentStepIndex ? 'bg-primary text-white' : 'bg-gray-100 text-gray-500 dark:bg-gray-700 dark:text-gray-300'"
            >
              <CheckCircle2 v-if="index < currentStepIndex" :size="15" />
              <span v-else>{{ index + 1 }}</span>
            </div>
            <span
              class="min-w-0 truncate text-sm font-semibold"
              :class="index <= currentStepIndex ? 'text-gray-950 dark:text-white' : 'text-gray-500 dark:text-gray-400'"
            >
              {{ step.label }}
            </span>
          </li>
        </ol>
      </nav>

      <section class="rounded-2xl border border-gray-200 bg-white p-5 shadow-sm dark:border-gray-700 dark:bg-gray-800 sm:p-6">
        <div v-if="loadingStatus" class="flex min-h-72 items-center justify-center text-sm text-gray-500 dark:text-gray-400">
          正在读取初始化状态...
        </div>

        <div v-else-if="restartRequired" class="space-y-5">
          <div>
            <div class="mb-3 flex h-11 w-11 items-center justify-center rounded-xl bg-amber-50 text-amber-600 dark:bg-amber-900/20 dark:text-amber-300">
              <RotateCw :size="22" />
            </div>
            <h2 class="text-xl font-bold text-gray-950 dark:text-white">数据库配置已保存</h2>
            <p class="mt-2 text-sm leading-6 text-gray-500 dark:text-gray-400">
              配置已写入 {{ savedConfigPath || '本地配置文件' }}。请重启服务后回到初始化页继续设置访问密码。
            </p>
          </div>
          <div class="rounded-xl border border-amber-200 bg-amber-50 px-4 py-3 text-sm text-amber-700 dark:border-amber-800 dark:bg-amber-900/20 dark:text-amber-200">
            重启前不会进入密码步骤，避免把访问密码写入旧数据库。
          </div>
        </div>

        <div v-else-if="currentStep === 'database'" class="space-y-5">
          <div>
            <div class="mb-3 flex h-11 w-11 items-center justify-center rounded-xl bg-blue-50 text-blue-600 dark:bg-blue-900/20 dark:text-blue-300">
              <Database :size="22" />
            </div>
            <h2 class="text-xl font-bold text-gray-950 dark:text-white">选择数据库</h2>
            <p class="mt-2 text-sm leading-6 text-gray-500 dark:text-gray-400">默认配置可直接继续。需要连接 MySQL 或 PostgreSQL 时再展开设置。</p>
          </div>

          <div class="border-y border-gray-100 py-4 dark:border-gray-700">
            <div class="min-w-0">
              <div class="text-xs font-semibold uppercase text-gray-400">当前数据库</div>
              <div class="mt-1 truncate text-base font-semibold text-gray-950 dark:text-white">{{ databaseLabel() }}</div>
              <div class="mt-1 truncate text-sm text-gray-500 dark:text-gray-400">{{ databaseSummary() }}</div>
            </div>
          </div>

          <div v-if="!showDatabaseForm" class="flex flex-col gap-2 sm:flex-row">
            <button
              type="button"
              class="h-11 rounded-xl border border-gray-200 px-4 text-sm font-semibold text-gray-700 transition hover:bg-gray-50 dark:border-gray-700 dark:text-gray-200 dark:hover:bg-gray-700"
              :disabled="!canEditDatabase"
              @click="revealDatabaseForm"
            >
              更换数据库
            </button>
            <button
              type="button"
              class="h-11 rounded-xl border border-gray-200 px-4 text-sm font-semibold text-gray-700 transition hover:bg-gray-50 dark:border-gray-700 dark:text-gray-200 dark:hover:bg-gray-700"
              :disabled="!canEditDatabase"
              aria-label="展开数据库高级设置"
              @click="revealAdvancedSettings"
            >
              高级设置
            </button>
          </div>
          <div v-else class="flex">
            <button
              type="button"
              class="h-11 rounded-xl border border-gray-200 px-4 text-sm font-semibold text-gray-700 transition hover:bg-gray-50 dark:border-gray-700 dark:text-gray-200 dark:hover:bg-gray-700"
              :disabled="!canEditDatabase"
              @click="cancelDatabaseChange"
            >
              取消更换
            </button>
          </div>

          <div v-if="showDatabaseForm" class="space-y-5 border-t border-gray-100 pt-5 dark:border-gray-700">
            <div>
              <label class="mb-2 block text-sm font-semibold text-gray-700 dark:text-gray-200">数据库类型</label>
              <div class="grid grid-cols-3 gap-2">
                <button
                  v-for="item in databaseDrivers"
                  :key="item.value"
                  type="button"
                  class="h-11 rounded-xl text-sm font-semibold transition"
                  :class="databaseForm.driver === item.value ? 'bg-primary text-white shadow-sm shadow-primary/20' : 'bg-gray-100 text-gray-600 hover:bg-gray-200 dark:bg-gray-700 dark:text-gray-300 dark:hover:bg-gray-600'"
                  :disabled="!canEditDatabase"
                  @click="setDatabaseDriver(item.value)"
                >
                  {{ item.label }}
                </button>
              </div>
            </div>

            <div v-if="usesSqlite" class="space-y-2">
              <label for="setup-sqlite-path" class="block text-sm font-semibold text-gray-700 dark:text-gray-200">SQLite 路径</label>
              <input
                id="setup-sqlite-path"
                v-model="databaseForm.path"
                type="text"
                class="h-11 w-full rounded-xl border border-gray-200 bg-white px-3 text-sm font-medium text-gray-900 outline-none transition focus:border-primary focus:ring-2 focus:ring-primary/15 dark:border-gray-700 dark:bg-gray-900 dark:text-white"
                :disabled="!canEditDatabase"
              />
            </div>

            <div v-else-if="useAdvancedDsn" class="space-y-2">
              <label for="setup-database-dsn" class="block text-sm font-semibold text-gray-700 dark:text-gray-200">数据库 DSN</label>
              <input
                id="setup-database-dsn"
                v-model="databaseForm.dsn"
                type="password"
                autocomplete="new-password"
                class="h-11 w-full rounded-xl border border-gray-200 bg-white px-3 text-sm font-medium text-gray-900 outline-none transition focus:border-primary focus:ring-2 focus:ring-primary/15 dark:border-gray-700 dark:bg-gray-900 dark:text-white"
                :disabled="!canEditDatabase"
              />
            </div>

            <div v-else class="space-y-4">
              <div class="grid gap-3 sm:grid-cols-[1fr_112px]">
                <div class="space-y-2">
                  <label for="setup-database-host" class="block text-sm font-semibold text-gray-700 dark:text-gray-200">主机</label>
                  <input
                    id="setup-database-host"
                    v-model="databaseForm.host"
                    type="text"
                    class="h-11 w-full rounded-xl border border-gray-200 bg-white px-3 text-sm font-medium text-gray-900 outline-none transition focus:border-primary focus:ring-2 focus:ring-primary/15 dark:border-gray-700 dark:bg-gray-900 dark:text-white"
                    :disabled="!canEditDatabase"
                  />
                </div>
                <div class="space-y-2">
                  <label for="setup-database-port" class="block text-sm font-semibold text-gray-700 dark:text-gray-200">端口</label>
                  <input
                    id="setup-database-port"
                    v-model.number="databaseForm.port"
                    type="number"
                    min="1"
                    class="h-11 w-full rounded-xl border border-gray-200 bg-white px-3 text-sm font-medium text-gray-900 outline-none transition focus:border-primary focus:ring-2 focus:ring-primary/15 dark:border-gray-700 dark:bg-gray-900 dark:text-white"
                    :disabled="!canEditDatabase"
                  />
                </div>
              </div>

              <div class="grid gap-3 sm:grid-cols-2">
                <div class="space-y-2">
                  <label for="setup-database-name" class="block text-sm font-semibold text-gray-700 dark:text-gray-200">数据库名</label>
                  <input
                    id="setup-database-name"
                    v-model="databaseForm.database"
                    type="text"
                    class="h-11 w-full rounded-xl border border-gray-200 bg-white px-3 text-sm font-medium text-gray-900 outline-none transition focus:border-primary focus:ring-2 focus:ring-primary/15 dark:border-gray-700 dark:bg-gray-900 dark:text-white"
                    :disabled="!canEditDatabase"
                  />
                </div>
                <div class="space-y-2">
                  <label for="setup-database-username" class="block text-sm font-semibold text-gray-700 dark:text-gray-200">用户名</label>
                  <input
                    id="setup-database-username"
                    v-model="databaseForm.username"
                    type="text"
                    class="h-11 w-full rounded-xl border border-gray-200 bg-white px-3 text-sm font-medium text-gray-900 outline-none transition focus:border-primary focus:ring-2 focus:ring-primary/15 dark:border-gray-700 dark:bg-gray-900 dark:text-white"
                    :disabled="!canEditDatabase"
                  />
                </div>
              </div>

              <div class="space-y-2">
                <label for="setup-database-password" class="block text-sm font-semibold text-gray-700 dark:text-gray-200">密码</label>
                <input
                  id="setup-database-password"
                  v-model="databaseForm.password"
                  type="password"
                  autocomplete="new-password"
                  class="h-11 w-full rounded-xl border border-gray-200 bg-white px-3 text-sm font-medium text-gray-900 outline-none transition focus:border-primary focus:ring-2 focus:ring-primary/15 dark:border-gray-700 dark:bg-gray-900 dark:text-white"
                  :disabled="!canEditDatabase"
                />
              </div>
            </div>

            <button
              type="button"
              class="flex h-11 w-full items-center justify-between rounded-xl border border-gray-200 px-4 text-left text-sm font-semibold text-gray-700 transition hover:bg-gray-50 dark:border-gray-700 dark:text-gray-200 dark:hover:bg-gray-700"
              :disabled="!canEditDatabase"
              :aria-expanded="showAdvancedSettings"
              aria-controls="setup-advanced-settings"
              :aria-label="showAdvancedSettings ? '收起数据库高级设置' : '展开数据库高级设置'"
              @click="toggleAdvancedSettings"
            >
              <span class="flex items-center gap-2"><Settings2 :size="16" /> 高级设置</span>
              <ChevronDown :size="18" class="transition" :class="showAdvancedSettings ? 'rotate-180' : ''" />
            </button>

            <div v-if="showAdvancedSettings" id="setup-advanced-settings" class="space-y-4 border-t border-gray-100 pt-4 dark:border-gray-700">
              <div v-if="!usesSqlite" class="flex items-center justify-between gap-3">
                <div>
                  <div class="text-sm font-semibold text-gray-800 dark:text-gray-100">使用 DSN 连接串</div>
                  <div class="text-xs text-gray-500 dark:text-gray-400">开启后将忽略主机、端口和用户名表单。</div>
                </div>
                <button
                  type="button"
                  class="h-11 rounded-lg px-3 text-xs font-bold transition"
                  :class="useAdvancedDsn ? 'bg-primary text-white' : 'bg-gray-100 text-gray-600 dark:bg-gray-700 dark:text-gray-300'"
                  :disabled="!canEditDatabase"
                  :aria-pressed="useAdvancedDsn"
                  @click="useAdvancedDsn = !useAdvancedDsn"
                >
                  {{ useAdvancedDsn ? '已开启' : '开启' }}
                </button>
              </div>

              <div v-if="!usesSqlite && !useAdvancedDsn" class="grid gap-3 sm:grid-cols-2">
                <div v-if="usesPostgres" class="space-y-2">
                  <label for="setup-database-ssl-mode" class="block text-sm font-semibold text-gray-700 dark:text-gray-200">SSL 模式</label>
                  <input
                    id="setup-database-ssl-mode"
                    v-model="databaseForm.ssl_mode"
                    type="text"
                    class="h-11 w-full rounded-xl border border-gray-200 bg-white px-3 text-sm font-medium text-gray-900 outline-none transition focus:border-primary focus:ring-2 focus:ring-primary/15 dark:border-gray-700 dark:bg-gray-900 dark:text-white"
                    :disabled="!canEditDatabase"
                  />
                </div>
                <div class="space-y-2">
                  <label for="setup-database-timezone" class="block text-sm font-semibold text-gray-700 dark:text-gray-200">时区</label>
                  <input
                    id="setup-database-timezone"
                    v-model="databaseForm.timezone"
                    type="text"
                    class="h-11 w-full rounded-xl border border-gray-200 bg-white px-3 text-sm font-medium text-gray-900 outline-none transition focus:border-primary focus:ring-2 focus:ring-primary/15 dark:border-gray-700 dark:bg-gray-900 dark:text-white"
                    :disabled="!canEditDatabase"
                  />
                </div>
              </div>

              <div class="grid gap-3 sm:grid-cols-2">
                <div class="space-y-2">
                  <label for="setup-database-max-open-conns" class="block text-sm font-semibold text-gray-700 dark:text-gray-200">最大连接</label>
                  <input
                    id="setup-database-max-open-conns"
                    v-model.number="databaseForm.max_open_conns"
                    type="number"
                    min="0"
                    class="h-11 w-full rounded-xl border border-gray-200 bg-white px-3 text-sm font-medium text-gray-900 outline-none transition focus:border-primary focus:ring-2 focus:ring-primary/15 dark:border-gray-700 dark:bg-gray-900 dark:text-white"
                    :disabled="!canEditDatabase"
                  />
                </div>
                <div class="space-y-2">
                  <label for="setup-database-max-idle-conns" class="block text-sm font-semibold text-gray-700 dark:text-gray-200">空闲连接</label>
                  <input
                    id="setup-database-max-idle-conns"
                    v-model.number="databaseForm.max_idle_conns"
                    type="number"
                    min="0"
                    class="h-11 w-full rounded-xl border border-gray-200 bg-white px-3 text-sm font-medium text-gray-900 outline-none transition focus:border-primary focus:ring-2 focus:ring-primary/15 dark:border-gray-700 dark:bg-gray-900 dark:text-white"
                    :disabled="!canEditDatabase"
                  />
                </div>
              </div>
            </div>
          </div>

          <div v-if="showDatabaseForm" class="grid gap-2 sm:grid-cols-[auto_1fr]">
            <button
              type="button"
              class="flex h-12 items-center justify-center rounded-xl border border-gray-200 px-4 text-sm font-semibold text-gray-700 transition hover:bg-gray-50 disabled:opacity-60 dark:border-gray-700 dark:text-gray-200 dark:hover:bg-gray-700"
              :disabled="databaseTesting || databaseSaving"
              @click="testDatabaseConnection"
            >
              {{ databaseTesting ? '测试中...' : databaseTested ? '连接正常' : '测试连接' }}
            </button>
            <button
              type="button"
              class="flex h-12 w-full items-center justify-center gap-2 rounded-xl bg-primary px-4 text-sm font-bold text-white shadow-sm shadow-primary/20 transition hover:bg-primary/90 disabled:opacity-60"
              :disabled="databaseSaving || databaseTesting"
              @click="applyDatabaseConfig"
            >
              <span>{{ databaseSaving ? '保存中...' : '测试并保存' }}</span>
              <ArrowRight v-if="!databaseSaving" :size="18" />
            </button>
          </div>
          <button
            v-else
            type="button"
            class="flex h-12 w-full items-center justify-center gap-2 rounded-xl bg-primary px-4 text-sm font-bold text-white shadow-sm shadow-primary/20 transition hover:bg-primary/90"
            @click="continueWithCurrentDatabase"
          >
            <span>继续使用当前配置</span>
            <ArrowRight :size="18" />
          </button>
        </div>

        <div v-else-if="currentStep === 'password'" class="space-y-5">
          <div>
            <div class="mb-3 flex h-11 w-11 items-center justify-center rounded-xl bg-green-50 text-green-600 dark:bg-green-900/20 dark:text-green-300">
              <Lock :size="22" />
            </div>
            <h2 class="text-xl font-bold text-gray-950 dark:text-white">设置访问密码</h2>
            <p class="mt-2 text-sm leading-6 text-gray-500 dark:text-gray-400">密码将用于进入本账本，至少 8 位。</p>
          </div>

          <div class="space-y-4 border-y border-gray-100 py-4 dark:border-gray-700">
            <div class="space-y-2">
              <label for="setup-access-password" class="block text-sm font-semibold text-gray-700 dark:text-gray-200">密码</label>
              <div class="relative">
                <input
                  id="setup-access-password"
                  v-model="password"
                  :type="showPassword ? 'text' : 'password'"
                  minlength="8"
                  class="h-12 w-full rounded-xl border border-gray-200 bg-white px-3 pr-14 text-sm font-medium text-gray-900 outline-none transition focus:border-primary focus:ring-2 focus:ring-primary/15 dark:border-gray-700 dark:bg-gray-900 dark:text-white"
                  autocomplete="new-password"
                  :disabled="creatingPassword"
                  @keyup.enter="createAccessPassword"
                />
                <button
                  type="button"
                  class="absolute right-0.5 top-1/2 flex h-11 w-11 -translate-y-1/2 items-center justify-center rounded-lg text-gray-400 transition hover:bg-gray-100 hover:text-gray-600 dark:hover:bg-gray-700 dark:hover:text-gray-300"
                  :aria-label="showPassword ? '隐藏密码' : '显示密码'"
                  @click="showPassword = !showPassword"
                >
                  <Eye v-if="showPassword" :size="19" />
                  <EyeOff v-else :size="19" />
                </button>
              </div>
            </div>

            <div class="space-y-2">
              <label for="setup-confirm-password" class="block text-sm font-semibold text-gray-700 dark:text-gray-200">确认密码</label>
              <div class="relative">
                <input
                  id="setup-confirm-password"
                  v-model="confirmPassword"
                  :type="showConfirmPassword ? 'text' : 'password'"
                  minlength="8"
                  class="h-12 w-full rounded-xl border border-gray-200 bg-white px-3 pr-14 text-sm font-medium text-gray-900 outline-none transition focus:border-primary focus:ring-2 focus:ring-primary/15 dark:border-gray-700 dark:bg-gray-900 dark:text-white"
                  autocomplete="new-password"
                  :disabled="creatingPassword"
                  @keyup.enter="createAccessPassword"
                />
                <button
                  type="button"
                  class="absolute right-0.5 top-1/2 flex h-11 w-11 -translate-y-1/2 items-center justify-center rounded-lg text-gray-400 transition hover:bg-gray-100 hover:text-gray-600 dark:hover:bg-gray-700 dark:hover:text-gray-300"
                  :aria-label="showConfirmPassword ? '隐藏确认密码' : '显示确认密码'"
                  @click="showConfirmPassword = !showConfirmPassword"
                >
                  <Eye v-if="showConfirmPassword" :size="19" />
                  <EyeOff v-else :size="19" />
                </button>
              </div>
            </div>
          </div>

          <div class="grid gap-2 sm:grid-cols-[auto_1fr]">
            <button
              type="button"
              class="flex h-12 items-center justify-center gap-2 rounded-xl border border-gray-200 px-4 text-sm font-semibold text-gray-700 transition hover:bg-gray-50 disabled:opacity-60 dark:border-gray-700 dark:text-gray-200 dark:hover:bg-gray-700"
              :disabled="creatingPassword"
              @click="backToDatabaseStep"
            >
              <ChevronLeft :size="18" />
              返回
            </button>
            <button
              type="button"
              class="flex h-12 items-center justify-center gap-2 rounded-xl bg-primary px-4 text-sm font-bold text-white shadow-sm shadow-primary/20 transition hover:bg-primary/90 disabled:opacity-60"
              :disabled="creatingPassword"
              @click="createAccessPassword"
            >
              <span>{{ creatingPassword ? '初始化中...' : '完成初始化' }}</span>
              <ArrowRight v-if="!creatingPassword" :size="18" />
            </button>
          </div>
        </div>

        <div v-else class="space-y-5">
          <div>
            <div class="mb-3 flex h-11 w-11 items-center justify-center rounded-xl bg-green-50 text-green-600 dark:bg-green-900/20 dark:text-green-300">
              <CheckCircle2 :size="24" />
            </div>
            <h2 class="text-xl font-bold text-gray-950 dark:text-white">初始化完成</h2>
            <p class="mt-2 text-sm leading-6 text-gray-500 dark:text-gray-400">账本已经准备好，可以进入使用。</p>
          </div>
          <button
            type="button"
            class="flex h-12 w-full items-center justify-center gap-2 rounded-xl bg-primary px-4 text-sm font-bold text-white shadow-sm shadow-primary/20 transition hover:bg-primary/90"
            @click="enterLedger"
          >
            <span>进入账本</span>
            <ArrowRight :size="18" />
          </button>
        </div>
      </section>
    </main>
  </div>
</template>
