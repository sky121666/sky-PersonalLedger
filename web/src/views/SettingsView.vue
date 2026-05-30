<script setup lang="ts">
import { ref, computed, onMounted } from 'vue'
import { useRouter } from 'vue-router'
import type { AxiosResponse } from 'axios'
import { useAuthStore } from '@/stores/auth'
import { useThemeStore } from '@/stores/theme'
import { authApi } from '@/api/auth'
import { statisticsApi } from '@/api/statistics'
import { accountApi } from '@/api/account'
import { toast } from '@/composables/useToast'
import {
  Lock, Upload, Download, Info, ChevronRight,
  User, Shield, Database, X, Check, LogOut, Wallet, Moon, HardDrive, Bell,
  FolderOpen, Target, Users, FileText, Copy, RefreshCw, Clock, Key, Trash2, Plus, Smartphone, Sparkles
} from 'lucide-vue-next'
import { notificationApi } from '@/api/notification'
import { systemApi } from '@/api/system'
import { apiTokenApi, type APIToken } from '@/api/apiToken'
import { get, post, put } from '@/utils/request'
import dayjs from 'dayjs'

const router = useRouter()
const authStore = useAuthStore()
const themeStore = useThemeStore()

// User stats
const userStats = ref({
  totalTransactions: 0,
  accountCount: 0,
  memberSince: dayjs().format('YYYY-MM-DD')
})

// Services / Functions (Merged from ManagementView)
const services = [
  { icon: Wallet, label: '账户管理', route: 'accounts', color: 'text-blue-500', bg: 'bg-blue-50 dark:bg-blue-900/20' },
  { icon: FolderOpen, label: '分类管理', route: 'categories', color: 'text-purple-500', bg: 'bg-purple-50 dark:bg-purple-900/20' },
  { icon: Target, label: '预算设置', route: 'budgets', color: 'text-orange-500', bg: 'bg-orange-50 dark:bg-orange-900/20' },
  { icon: Bell, label: '负债管理', route: 'reminders', color: 'text-pink-500', bg: 'bg-pink-50 dark:bg-pink-900/20' },
  { icon: Users, label: '借贷往来', route: 'lendings', color: 'text-teal-500', bg: 'bg-teal-50 dark:bg-teal-900/20' },
  { icon: Users, label: '家庭成员', route: 'family', color: 'text-emerald-500', bg: 'bg-emerald-50 dark:bg-emerald-900/20' },
  { icon: Sparkles, label: 'AI 分析', route: 'ai', color: 'text-cyan-500', bg: 'bg-cyan-50 dark:bg-cyan-900/20' },
  { icon: FileText, label: '年度报告', route: 'report', color: 'text-indigo-500', bg: 'bg-indigo-50 dark:bg-indigo-900/20' }
]

onMounted(async () => {
  try {
    const [overview, accounts, profile] = await Promise.all([
      statisticsApi.getOverview(),
      accountApi.getList(),
      authApi.getProfile()
    ])
    userStats.value.totalTransactions = overview.transaction_count || 0
    userStats.value.accountCount = accounts.list?.length || 0
    profileForm.value = {
      nickname: profile.nickname || '',
      email: profile.email || '',
      avatar: profile.avatar || '',
      bio: profile.bio || ''
    }
  } catch (e) {
    console.error('Load user stats failed:', e)
  }
})

function navigateTo(name: string) {
  router.push({ name })
}

// Modal States
const showLogoutModal = ref(false)
const showAboutModal = ref(false)
const showPasswordModal = ref(false)
const showRestoreModal = ref(false)
const showSecurityModal = ref(false)
const showProfileModal = ref(false)
const showAutoBackupModal = ref(false)

// Auto backup form
const autoBackupForm = ref({
  enabled: false,
  frequency: 'daily',
  hour: 3,
  max_backups: 10
})
const autoBackupLoading = ref(false)
const autoBackupFiles = ref<{filename: string, size: number, created_at: string}[]>([])

interface UploadResult {
  url: string
}

interface AutoBackupSettings {
  enabled: boolean
  frequency: string
  hour: number
  max_backups: number
}

interface AutoBackupListResponse {
  files: {filename: string, size: number, created_at: string}[]
}

// Profile form
const profileForm = ref({
  nickname: '',
  email: '',
  avatar: '',
  bio: ''
})
const profileLoading = ref(false)
const avatarUploading = ref(false)

// Security entry path
const entryPathEnabled = ref(false)
const entryPath = ref('')
const entryPathLoading = ref(false)
const entryFullUrl = computed(() => window.location.origin + entryPath.value)

// API Token
const showApiTokenModal = ref(false)
const apiTokens = ref<APIToken[]>([])
const apiTokenLoading = ref(false)
const newTokenName = ref('')
const newTokenExpiry = ref(0) // 0 = never
const createdToken = ref<string | null>(null)

// Password form
const passwordForm = ref({
  oldPassword: '',
  newPassword: '',
  confirmPassword: ''
})
const passwordLoading = ref(false)
const passwordError = ref('')
const passwordSuccess = ref(false)

// Backup & Restore
const backupLoading = ref(false)
const restoreLoading = ref(false)
const restoreFile = ref<File | null>(null)

// Notification settings
const showNotificationModal = ref(false)
const notificationLoading = ref(false)
const notificationForm = ref({
  enabled: false,
  wecom_enabled: false,
  wecom_webhook: '',
  dingtalk_enabled: false,
  dingtalk_webhook: '',
  dingtalk_secret: '',
  email_enabled: false,
  smtp_host: '',
  smtp_port: 587,
  smtp_user: '',
  smtp_password: '',
  smtp_from: '',
  email_to: '',
  webhook_enabled: false,
  webhook_url: '',
  webhook_secret: '',
  notify_payment_due: true,
  notify_budget_alert: true,
  notify_lending_due: true,
  notify_annual_report: true,
  advance_days: 3
})
const activeNotifyTab = ref<'wecom' | 'dingtalk' | 'email' | 'webhook'>('wecom')
const testingChannel = ref<string | null>(null)

const menuGroups = [
  {
    title: '系统与安全',
    items: [
      { icon: Moon, label: '深色模式', desc: '切换显示外观', action: () => themeStore.toggle(), color: 'text-indigo-500', bg: 'bg-indigo-50 dark:bg-indigo-900/30', isToggle: true },
      { icon: Bell, label: '通知设置', desc: '消息提醒配置', action: openNotificationModal, color: 'text-orange-500', bg: 'bg-orange-50 dark:bg-orange-900/30' },
      { icon: Lock, label: '修改密码', desc: '更新登录密码', action: openPasswordModal, color: 'text-green-500', bg: 'bg-green-50 dark:bg-green-900/30' },
      { icon: Shield, label: '安全入口', desc: '防止暴力破解', action: openSecurityModal, color: 'text-red-500', bg: 'bg-red-50 dark:bg-red-900/30' },
      { icon: Smartphone, label: 'API Token', desc: 'App/API 访问令牌', action: openApiTokenModal, color: 'text-cyan-500', bg: 'bg-cyan-50 dark:bg-cyan-900/30' }
    ]
  },
  {
    title: '数据管理',
    items: [
      { icon: HardDrive, label: '数据备份', desc: '导出全部数据', action: handleBackup, color: 'text-blue-500', bg: 'bg-blue-50 dark:bg-blue-900/30' },
      { icon: Download, label: '恢复备份', desc: '导入数据文件', action: () => showRestoreModal.value = true, color: 'text-purple-500', bg: 'bg-purple-50 dark:bg-purple-900/30' },
      { icon: Clock, label: '自动备份', desc: '定时自动备份数据', action: openAutoBackupModal, color: 'text-green-500', bg: 'bg-green-50 dark:bg-green-900/30' },
    ]
  },
  {
    title: '关于',
    items: [
      { icon: Info, label: '关于应用', desc: '版本 v1.0.0', action: () => { showAboutModal.value = true }, color: 'text-gray-500', bg: 'bg-gray-100 dark:bg-gray-800' }
    ]
  }
]

function handleLogout() {
  authStore.logout()
  router.replace('/login')
}

// Profile functions
async function openProfileModal() {
  showProfileModal.value = true
  profileLoading.value = true
  try {
    const profile = await authApi.getProfile()
    profileForm.value = {
      nickname: profile.nickname || '',
      email: profile.email || '',
      avatar: profile.avatar || '',
      bio: profile.bio || ''
    }
  } catch (e) {
    console.error('Load profile failed:', e)
  } finally {
    profileLoading.value = false
  }
}

async function saveProfile() {
  profileLoading.value = true
  try {
    await authApi.updateProfile(profileForm.value)
    toast.success('保存成功')
    showProfileModal.value = false
  } catch (e: any) {
    toast.error(e.message || '保存失败')
  } finally {
    profileLoading.value = false
  }
}

async function handleAvatarUpload(e: Event) {
  const target = e.target as HTMLInputElement
  if (!target.files || !target.files[0]) return
  
  const file = target.files[0]
  if (!file.type.startsWith('image/')) {
    toast.error('请选择图片文件')
    return
  }
  
  avatarUploading.value = true
  try {
    const formData = new FormData()
    formData.append('file', file)

    const result = await post<UploadResult>('/upload/avatar', formData, {
      headers: { 'Content-Type': 'multipart/form-data' }
    })
    profileForm.value.avatar = result.url
    toast.success('头像上传成功')
  } catch (e: any) {
    toast.error(e.message || '上传失败')
  } finally {
    avatarUploading.value = false
  }
}

// Security entry path functions
async function openSecurityModal() {
  showSecurityModal.value = true
  entryPathLoading.value = true
  try {
    const res = await systemApi.getEntryPath()
    entryPath.value = res.entry_path
    entryPathEnabled.value = res.enabled
  } catch (e) {
    console.error('Load entry path failed:', e)
  } finally {
    entryPathLoading.value = false
  }
}

async function saveEntryPath() {
  entryPathLoading.value = true
  try {
    const res = await systemApi.setEntryPath(entryPath.value)
    entryPath.value = res.entry_path
    entryPathEnabled.value = res.enabled
    toast.success('入口路径已更新')
    if (res.entry_path) {
      toast.info(`新入口: ${window.location.origin}${res.entry_path}`)
    }
  } catch (e) {
    toast.error('保存失败')
  } finally {
    entryPathLoading.value = false
  }
}

async function generateEntryPath() {
  entryPathLoading.value = true
  try {
    const res = await systemApi.generateEntryPath()
    entryPath.value = res.entry_path
    entryPathEnabled.value = res.enabled
    toast.success('已生成随机入口路径')
  } catch (e) {
    toast.error('生成失败')
  } finally {
    entryPathLoading.value = false
  }
}

async function disableEntryPath() {
  entryPathLoading.value = true
  try {
    await systemApi.disableEntryPath()
    entryPath.value = ''
    entryPathEnabled.value = false
    toast.success('安全入口已禁用')
  } catch (e) {
    toast.error('禁用失败')
  } finally {
    entryPathLoading.value = false
  }
}

function copyEntryUrl() {
  const url = window.location.origin + entryPath.value
  navigator.clipboard.writeText(url)
  toast.success('已复制到剪贴板')
}

// API Token functions
async function openApiTokenModal() {
  showApiTokenModal.value = true
  createdToken.value = null
  newTokenName.value = ''
  newTokenExpiry.value = 0
  await loadApiTokens()
}

async function loadApiTokens() {
  apiTokenLoading.value = true
  try {
    const res = await apiTokenApi.list()
    apiTokens.value = res.list || []
  } catch (e) {
    console.error('Load API tokens failed:', e)
  } finally {
    apiTokenLoading.value = false
  }
}

async function createApiToken() {
  if (!newTokenName.value.trim()) {
    toast.error('请输入令牌名称')
    return
  }
  apiTokenLoading.value = true
  try {
    const res = await apiTokenApi.create({
      name: newTokenName.value.trim(),
      expires_in_days: newTokenExpiry.value
    })
    createdToken.value = res.token
    toast.success('令牌创建成功，请立即复制保存')
    await loadApiTokens()
    newTokenName.value = ''
  } catch (e: any) {
    toast.error(e.message || '创建失败')
  } finally {
    apiTokenLoading.value = false
  }
}

async function deleteApiToken(id: number) {
  if (!confirm('确定要删除此令牌吗？删除后使用此令牌的应用将无法访问。')) return
  apiTokenLoading.value = true
  try {
    await apiTokenApi.delete(id)
    toast.success('令牌已删除')
    await loadApiTokens()
  } catch (e: any) {
    toast.error(e.message || '删除失败')
  } finally {
    apiTokenLoading.value = false
  }
}

function copyToken(token: string) {
  navigator.clipboard.writeText(token)
  toast.success('已复制到剪贴板')
}

// Notification functions
async function openNotificationModal() {
  showNotificationModal.value = true
  notificationLoading.value = true
  try {
    const settings = await notificationApi.getSettings()
    Object.assign(notificationForm.value, settings)
    notificationForm.value.smtp_password = ''
  } catch (e) {
    console.error('Load notification settings failed:', e)
  } finally {
    notificationLoading.value = false
  }
}

async function saveNotificationSettings() {
  notificationLoading.value = true
  try {
    await notificationApi.updateSettings(notificationForm.value)
    toast.success('保存成功')
    showNotificationModal.value = false
  } catch (e: any) {
    toast.error(e.message || '保存失败')
  } finally {
    notificationLoading.value = false
  }
}

async function testNotification(channel: string) {
  testingChannel.value = channel
  try {
    let result
    switch (channel) {
      case 'wecom':
        if (!notificationForm.value.wecom_webhook) {
          toast.warning('请填写企业微信Webhook地址')
          return
        }
        result = await notificationApi.testWecom(notificationForm.value.wecom_webhook)
        break
      case 'dingtalk':
        if (!notificationForm.value.dingtalk_webhook) {
          toast.warning('请填写钉钉Webhook地址')
          return
        }
        result = await notificationApi.testDingtalk(notificationForm.value.dingtalk_webhook, notificationForm.value.dingtalk_secret)
        break
      case 'email':
        if (!notificationForm.value.smtp_host) {
          toast.warning('请填写SMTP服务器配置')
          return
        }
        result = await notificationApi.testEmail({
          smtp_host: notificationForm.value.smtp_host,
          smtp_port: notificationForm.value.smtp_port,
          smtp_user: notificationForm.value.smtp_user,
          smtp_password: notificationForm.value.smtp_password,
          smtp_from: notificationForm.value.smtp_from
        })
        break
      case 'webhook':
        if (!notificationForm.value.webhook_url) {
          toast.warning('请填写Webhook地址')
          return
        }
        result = await notificationApi.testWebhook(notificationForm.value.webhook_url, notificationForm.value.webhook_secret)
        break
    }
    if (result?.success) {
      toast.success('测试成功')
    } else {
      toast.error(result?.message || '测试失败')
    }
  } catch (e: any) {
    toast.error(e.message || '测试失败')
  } finally {
    testingChannel.value = null
  }
}

// Password
function openPasswordModal() {
  passwordForm.value = { oldPassword: '', newPassword: '', confirmPassword: '' }
  passwordError.value = ''
  passwordSuccess.value = false
  showPasswordModal.value = true
}

async function handleChangePassword() {
  passwordError.value = ''
  
  if (passwordForm.value.newPassword.length < 8) {
    passwordError.value = '新密码至少8位'
    return
  }
  if (passwordForm.value.newPassword !== passwordForm.value.confirmPassword) {
    passwordError.value = '两次密码不一致'
    return
  }
  
  passwordLoading.value = true
  try {
    await authApi.changePassword(passwordForm.value.oldPassword, passwordForm.value.newPassword)
    passwordSuccess.value = true
    setTimeout(() => {
      showPasswordModal.value = false
      authStore.logout()
      router.replace('/login')
    }, 1500)
  } catch (e: any) {
    passwordError.value = e.message || '修改失败'
  } finally {
    passwordLoading.value = false
  }
}

function downloadBlob(blob: Blob, filename: string) {
  const url = URL.createObjectURL(blob)
  const a = document.createElement('a')
  a.href = url
  a.download = filename
  a.click()
  URL.revokeObjectURL(url)
}

// Backup
async function handleBackup() {
  backupLoading.value = true
  toast.info('正在创建备份...')
  try {
    const response = await get<AxiosResponse<Blob>>('/backup', {
      responseType: 'blob'
    })
    const blob = response.data
    const filename = `backup_${dayjs().format('YYYYMMDD_HHmmss')}.json`
    downloadBlob(blob, filename)
    toast.success('备份成功')
  } catch (e: any) {
    toast.error(e.message || '备份失败')
  } finally {
    backupLoading.value = false
  }
}

// Restore
function handleRestoreFileSelect(e: Event) {
  const target = e.target as HTMLInputElement
  if (target.files && target.files[0]) {
    restoreFile.value = target.files[0]
  }
}

async function handleRestore() {
  if (!restoreFile.value) {
    toast.warning('请选择备份文件')
    return
  }

  restoreLoading.value = true
  try {
    const formData = new FormData()
    formData.append('file', restoreFile.value)

    await post('/restore', formData, {
      headers: { 'Content-Type': 'multipart/form-data' }
    })
    showRestoreModal.value = false
    restoreFile.value = null
    toast.success(`恢复成功`)
    // Reload page to reflect changes
    setTimeout(() => window.location.reload(), 1000)
  } catch (e: any) {
    toast.error(e.message || '恢复失败')
  } finally {
    restoreLoading.value = false
  }
}

// Auto backup functions
async function openAutoBackupModal() {
  showAutoBackupModal.value = true
  autoBackupLoading.value = true
  try {
    const [settings, files] = await Promise.all([
      get<AutoBackupSettings>('/backup/auto/settings'),
      get<AutoBackupListResponse>('/backup/auto/list')
    ])
    autoBackupForm.value = {
      enabled: settings.enabled || false,
      frequency: settings.frequency || 'daily',
      hour: settings.hour ?? 3,
      max_backups: settings.max_backups || 10
    }
    autoBackupFiles.value = files.files || []
  } catch (e) {
    console.error('Load auto backup settings failed:', e)
  } finally {
    autoBackupLoading.value = false
  }
}

async function saveAutoBackupSettings() {
  autoBackupLoading.value = true
  try {
    await put('/backup/auto/settings', autoBackupForm.value)
    toast.success('自动备份设置已保存')
    showAutoBackupModal.value = false
  } catch (e: any) {
    toast.error(e.message || '保存失败')
  } finally {
    autoBackupLoading.value = false
  }
}

async function triggerAutoBackup() {
  autoBackupLoading.value = true
  try {
    await post('/backup/auto/trigger')
    toast.success('备份已触发')
    // Reload file list
    const files = await get<AutoBackupListResponse>('/backup/auto/list')
    autoBackupFiles.value = files.files || []
  } catch (e: any) {
    toast.error(e.message || '备份失败')
  } finally {
    autoBackupLoading.value = false
  }
}

function formatFileSize(bytes: number) {
  if (bytes < 1024) return bytes + ' B'
  if (bytes < 1024 * 1024) return (bytes / 1024).toFixed(1) + ' KB'
  return (bytes / 1024 / 1024).toFixed(1) + ' MB'
}
</script>

<template>
  <div class="min-h-full bg-[#F2F2F7] dark:bg-black pb-8">
    <!-- Header / User Profile -->
    <div class="bg-white/70 dark:bg-[#1C1C1E]/70 pt-4 pb-4 px-4 md:px-8 sticky top-0 z-30 backdrop-blur-xl border-b border-gray-200/50 dark:border-white/10">
       <div class="max-w-3xl mx-auto flex items-center justify-between">
          <button class="flex items-center gap-4 text-left hover:opacity-80 transition" @click="openProfileModal">
            <div class="w-16 h-16 rounded-full bg-gradient-to-br from-gray-100 to-gray-200 dark:from-gray-700 dark:to-gray-800 flex items-center justify-center overflow-hidden shadow-inner border border-white/20">
               <img v-if="profileForm.avatar" :src="profileForm.avatar" class="w-full h-full object-cover" />
               <User v-else class="text-gray-400" :size="32" />
            </div>
            <div>
               <h1 class="text-xl font-bold text-gray-900 dark:text-white">{{ profileForm.nickname || '用户账户' }}</h1>
               <div class="text-sm text-gray-500 dark:text-gray-400 mt-0.5">{{ profileForm.bio || '点击编辑个人信息' }}</div>
               <!-- Badges -->
               <div class="flex items-center gap-2 mt-2">
                  <div class="flex items-center gap-1 bg-green-50 dark:bg-green-900/20 text-green-600 dark:text-green-400 px-2 py-0.5 rounded text-[10px] font-medium border border-green-100 dark:border-green-900/30">
                    <Shield :size="10" />
                    <span>私有部署</span>
                  </div>
                  <div class="flex items-center gap-1 bg-blue-50 dark:bg-blue-900/20 text-blue-600 dark:text-blue-400 px-2 py-0.5 rounded text-[10px] font-medium border border-blue-100 dark:border-blue-900/30">
                    <Database :size="10" />
                    <span>服务端数据库</span>
                  </div>
               </div>
            </div>
          </button>
          <button 
            class="p-2.5 bg-gray-100/50 dark:bg-white/5 hover:bg-red-50 dark:hover:bg-red-900/20 text-gray-400 hover:text-red-500 rounded-full transition-all"
            @click="showLogoutModal = true"
          >
             <LogOut :size="20" />
          </button>
       </div>
    </div>

    <div class="max-w-3xl mx-auto px-4 md:px-8 py-6 space-y-6">
       <!-- Stats Cards -->
       <div class="grid grid-cols-2 gap-4">
          <div class="bg-white/70 dark:bg-[#1C1C1E]/70 backdrop-blur-xl rounded-[20px] p-4 flex flex-col items-center justify-center gap-1 shadow-sm border border-white/40 dark:border-white/5">
             <div class="text-2xl font-bold font-nums text-gray-900 dark:text-white">{{ userStats.totalTransactions }}</div>
             <div class="text-xs text-gray-500">累计记账</div>
          </div>
          <div class="bg-white/70 dark:bg-[#1C1C1E]/70 backdrop-blur-xl rounded-[20px] p-4 flex flex-col items-center justify-center gap-1 shadow-sm border border-white/40 dark:border-white/5">
             <div class="text-2xl font-bold font-nums text-gray-900 dark:text-white">{{ userStats.accountCount }}</div>
             <div class="text-xs text-gray-500">账户数量</div>
          </div>
       </div>

       <!-- Services Grid (Management) -->
       <div class="bg-white/70 dark:bg-[#1C1C1E]/70 backdrop-blur-xl rounded-[24px] p-5 shadow-sm border border-white/40 dark:border-white/5">
          <h3 class="text-sm font-bold text-gray-900 dark:text-white mb-5 px-1">常用功能</h3>
          <div class="grid grid-cols-4 gap-y-6">
             <button 
                v-for="item in services" 
                :key="item.route" 
                class="flex flex-col items-center gap-2 group"
                @click="navigateTo(item.route)"
              >
                <div 
                  class="w-12 h-12 rounded-[18px] flex items-center justify-center transition-transform duration-300 group-hover:scale-105 shadow-sm" 
                  :class="item.bg"
                >
                   <component :is="item.icon" :size="24" :class="item.color" />
                </div>
                <div class="text-[11px] font-medium text-gray-600 dark:text-gray-300">{{ item.label }}</div>
             </button>
          </div>
       </div>

      <!-- Settings Groups -->
      <div class="space-y-6">
        <div v-for="(group, gi) in menuGroups" :key="gi">
          <h3 class="text-xs font-bold text-gray-400 dark:text-gray-500 uppercase tracking-wider mb-2 px-3">{{ group.title }}</h3>
          <div class="bg-white/70 dark:bg-[#1C1C1E]/70 backdrop-blur-xl rounded-[20px] overflow-hidden shadow-sm border border-white/40 dark:border-white/5">
            <button
              v-for="(item, ii) in group.items"
              :key="ii"
              class="w-full flex items-center px-4 py-3.5 hover:bg-black/5 dark:hover:bg-white/5 transition active:bg-black/10 dark:active:bg-white/10 group border-b border-gray-100/50 dark:border-white/5 last:border-b-0"
              @click="item.action"
            >
              <div 
                class="w-8 h-8 rounded-[10px] flex items-center justify-center mr-3.5 transition-transform group-hover:scale-105 shadow-sm"
                :class="item.bg"
              >
                <component :is="item.icon" :size="16" :class="item.color" />
              </div>
              <div class="flex-1 text-left">
                <div class="text-[15px] font-medium text-gray-900 dark:text-white">{{ item.label }}</div>
              </div>
              
              <!-- Toggle Switch for theme -->
              <div v-if="(item as any).isToggle" class="relative mr-1">
                <div 
                  class="w-10 h-6 rounded-full transition-colors duration-200"
                  :class="themeStore.isDark ? 'bg-primary' : 'bg-gray-300 dark:bg-gray-600'"
                >
                  <div 
                    class="absolute top-1 w-4 h-4 bg-white rounded-full shadow-md transition-transform duration-200"
                    :class="themeStore.isDark ? 'translate-x-5' : 'translate-x-1'"
                  ></div>
                </div>
              </div>
              <ChevronRight v-else :size="16" class="text-gray-300 dark:text-gray-600 group-hover:text-gray-400 transition-colors" />
            </button>
          </div>
        </div>
      </div>

      <!-- Version -->
      <div class="text-center py-4">
        <p class="text-xs text-gray-400">Personal Ledger v1.0.0</p>
      </div>
    </div>

    <!-- Logout Confirm Modal -->
    <Teleport to="body">
      <div v-if="showLogoutModal" class="fixed inset-0 z-50 flex items-center justify-center p-4">
        <div class="absolute inset-0 bg-black/40 backdrop-blur-sm" @click="showLogoutModal = false"></div>
        <div class="relative bg-white/90 dark:bg-[#1C1C1E]/90 backdrop-blur-xl rounded-[20px] p-6 w-[280px] shadow-2xl animate-in zoom-in-95 duration-200 text-center">
          <div class="w-12 h-12 bg-red-100 dark:bg-red-900/30 rounded-full flex items-center justify-center mb-4 mx-auto text-red-500">
            <LogOut :size="24" />
          </div>
          <h3 class="text-lg font-bold text-gray-900 dark:text-white mb-2">确认退出</h3>
          <p class="text-[13px] text-gray-500 dark:text-gray-400 mb-6 leading-relaxed">确定要退出登录吗？下次登录需要重新输入密码。</p>
          <div class="flex gap-3 justify-center border-t border-gray-200/50 dark:border-white/10 pt-4 -mx-6 -mb-2">
            <button
              class="flex-1 py-2 text-[17px] text-blue-500 font-medium active:opacity-70 transition"
              @click="showLogoutModal = false"
            >
              取消
            </button>
            <div class="w-px bg-gray-200/50 dark:bg-white/10"></div>
            <button
              class="flex-1 py-2 text-[17px] text-red-500 font-medium active:opacity-70 transition"
              @click="handleLogout"
            >
              退出
            </button>
          </div>
        </div>
      </div>
    </Teleport>

    <!-- About Modal -->
    <Teleport to="body">
      <div v-if="showAboutModal" class="fixed inset-0 z-50 flex items-center justify-center p-4">
        <div class="absolute inset-0 bg-black/40 backdrop-blur-sm" @click="showAboutModal = false"></div>
        <div class="relative bg-white/90 dark:bg-[#1C1C1E]/90 backdrop-blur-xl rounded-[24px] p-6 w-full max-w-sm shadow-2xl animate-in zoom-in-95 duration-200 border border-white/20 dark:border-white/10">
          <div class="w-20 h-20 bg-gradient-to-br from-primary to-blue-600 rounded-[20px] flex items-center justify-center mx-auto mb-6 shadow-xl shadow-primary/20">
            <Wallet class="text-white" :size="40" />
          </div>
          <h3 class="text-2xl font-bold mb-2 text-gray-900 dark:text-white text-center">Personal Ledger</h3>
          <p class="text-gray-500 dark:text-gray-400 mb-8 leading-relaxed text-center text-sm">
            简单、安全、优雅的<br>个人记账助手
          </p>
          
          <div class="bg-gray-50/50 dark:bg-white/5 rounded-2xl p-4 mb-8 text-xs text-gray-500 dark:text-gray-400 space-y-2 border border-gray-100/50 dark:border-white/5">
            <div class="flex justify-between">
              <span>当前版本</span>
              <span class="font-medium text-gray-900 dark:text-white">v1.0.0</span>
            </div>
            <div class="flex justify-between">
              <span>开源协议</span>
              <span class="font-medium text-gray-900 dark:text-white">MIT License</span>
            </div>
            <div class="flex justify-between">
              <span>开发者</span>
              <span class="font-medium text-gray-900 dark:text-white">Sky</span>
            </div>
          </div>

          <button
            class="w-full py-3 bg-black dark:bg-white text-white dark:text-black rounded-xl font-medium hover:opacity-80 transition shadow-lg"
            @click="showAboutModal = false"
          >
            知道了
          </button>
        </div>
      </div>
    </Teleport>

    <!-- Password Modal -->
    <Teleport to="body">
      <div v-if="showPasswordModal" class="fixed inset-0 z-50 flex items-center justify-center p-4">
        <div class="absolute inset-0 bg-black/40 backdrop-blur-sm" @click="showPasswordModal = false"></div>
        <div class="relative bg-white/90 dark:bg-[#1C1C1E]/90 backdrop-blur-xl rounded-[24px] w-full max-w-sm shadow-2xl animate-in zoom-in-95 duration-200 border border-white/20 dark:border-white/10">
          <div class="flex items-center justify-between p-6 border-b border-gray-100/50 dark:border-white/10">
            <h3 class="text-lg font-bold text-gray-900 dark:text-white">修改密码</h3>
            <button class="p-2 hover:bg-black/5 dark:hover:bg-white/10 rounded-full transition" @click="showPasswordModal = false">
              <X :size="20" class="text-gray-500" />
            </button>
          </div>
          
          <div v-if="passwordSuccess" class="p-10 text-center">
            <div class="w-16 h-16 bg-green-100 dark:bg-green-900/30 rounded-full flex items-center justify-center mx-auto mb-4 animate-bounce">
              <Check class="text-green-500" :size="32" />
            </div>
            <h4 class="text-lg font-bold text-gray-900 dark:text-white mb-2">修改成功</h4>
            <p class="text-gray-500 dark:text-gray-400 text-sm">即将重新登录...</p>
          </div>
          
          <div v-else class="p-6 space-y-4">
            <div class="space-y-1.5">
              <label class="text-xs font-bold text-gray-400 uppercase tracking-wider">当前密码</label>
              <input
                v-model="passwordForm.oldPassword"
                type="password"
                class="w-full h-12 px-4 bg-gray-50 dark:bg-black/30 rounded-xl border-0 outline-none focus:ring-2 focus:ring-primary/20 transition-all font-medium text-gray-900 dark:text-white"
              />
            </div>
            <div class="space-y-1.5">
              <label class="text-xs font-bold text-gray-400 uppercase tracking-wider">新密码</label>
              <input
                v-model="passwordForm.newPassword"
                type="password"
                placeholder="至少8位"
                class="w-full h-12 px-4 bg-gray-50 dark:bg-black/30 rounded-xl border-0 outline-none focus:ring-2 focus:ring-primary/20 transition-all font-medium text-gray-900 dark:text-white placeholder:text-gray-400"
              />
            </div>
            <div class="space-y-1.5">
              <label class="text-xs font-bold text-gray-400 uppercase tracking-wider">确认新密码</label>
              <input
                v-model="passwordForm.confirmPassword"
                type="password"
                placeholder="再次输入新密码"
                class="w-full h-12 px-4 bg-gray-50 dark:bg-black/30 rounded-xl border-0 outline-none focus:ring-2 focus:ring-primary/20 transition-all font-medium text-gray-900 dark:text-white placeholder:text-gray-400"
              />
            </div>
            
            <div v-if="passwordError" class="text-red-500 text-xs flex items-center gap-2 bg-red-50 dark:bg-red-900/30 p-3 rounded-xl">
              <Info :size="14" />
              {{ passwordError }}
            </div>

            <button
              class="w-full h-12 bg-primary text-white rounded-xl font-bold hover:bg-primary/90 disabled:opacity-50 disabled:cursor-not-allowed transition shadow-lg shadow-primary/20 mt-2"
              :disabled="passwordLoading"
              @click="handleChangePassword"
            >
              {{ passwordLoading ? '修改中...' : '确认修改' }}
            </button>
          </div>
        </div>
      </div>
    </Teleport>

    <!-- Restore Modal -->
    <Teleport to="body">
      <div v-if="showRestoreModal" class="fixed inset-0 z-50 flex items-center justify-center p-4">
        <div class="absolute inset-0 bg-black/40 backdrop-blur-sm" @click="showRestoreModal = false"></div>
        <div class="relative bg-white/90 dark:bg-[#1C1C1E]/90 backdrop-blur-xl rounded-[24px] p-6 w-full max-w-sm shadow-2xl animate-in zoom-in-95 duration-200 border border-white/20 dark:border-white/10">
          <div class="flex items-center gap-4 mb-6">
            <div class="w-12 h-12 bg-blue-100 dark:bg-blue-900/30 rounded-2xl flex items-center justify-center text-blue-600">
              <Download :size="24" />
            </div>
            <div>
              <h3 class="text-lg font-bold text-gray-900 dark:text-white">恢复备份</h3>
              <p class="text-gray-500 dark:text-gray-400 text-sm">选择备份文件恢复数据</p>
            </div>
          </div>
          
          <div class="space-y-4">
            <div class="bg-amber-50 dark:bg-amber-900/20 border border-amber-200 dark:border-amber-800 rounded-xl p-3 text-xs text-amber-700 dark:text-amber-400 leading-relaxed">
              ⚠️ 恢复备份将覆盖当前所有数据，请谨慎操作。建议先备份当前数据。
            </div>
            
            <label class="block">
              <div 
                class="border-2 border-dashed border-gray-300 dark:border-gray-600 rounded-2xl p-6 text-center hover:border-blue-400 dark:hover:border-blue-500 hover:bg-blue-50/50 dark:hover:bg-blue-900/20 transition-all cursor-pointer group"
                :class="restoreFile ? 'border-blue-400 bg-blue-50 dark:bg-blue-900/30' : ''"
              >
                <input 
                  type="file" 
                  accept=".json" 
                  class="hidden" 
                  @change="handleRestoreFileSelect"
                />
                <div v-if="restoreFile" class="text-blue-600">
                  <Check :size="32" class="mx-auto mb-2" />
                  <p class="font-medium text-sm">{{ restoreFile.name }}</p>
                  <p class="text-xs text-gray-400 mt-1">点击重新选择</p>
                </div>
                <div v-else class="text-gray-400 group-hover:text-blue-500 transition-colors">
                  <Upload :size="32" class="mx-auto mb-2" />
                  <p class="font-medium text-sm">点击选择文件</p>
                  <p class="text-xs mt-1 opacity-70">支持 JSON 格式</p>
                </div>
              </div>
            </label>

            <div class="flex gap-3">
              <button
                class="flex-1 py-3 border border-gray-200 dark:border-gray-600 rounded-xl text-gray-700 dark:text-gray-300 font-medium hover:bg-gray-50 dark:hover:bg-gray-700 transition"
                @click="showRestoreModal = false; restoreFile = null"
              >
                取消
              </button>
              <button
                class="flex-1 py-3 bg-blue-500 text-white rounded-xl font-medium hover:bg-blue-600 transition shadow-lg shadow-blue-500/30"
                :disabled="!restoreFile || restoreLoading"
                @click="handleRestore"
              >
                {{ restoreLoading ? '恢复中...' : '开始恢复' }}
              </button>
            </div>
          </div>
        </div>
      </div>
    </Teleport>

    <!-- Notification Settings Modal -->
    <Teleport to="body">
      <div v-if="showNotificationModal" class="fixed inset-0 z-50 flex items-center justify-center p-4">
        <div class="absolute inset-0 bg-black/40 backdrop-blur-sm" @click="showNotificationModal = false"></div>
        <div class="relative bg-white/95 dark:bg-[#1C1C1E]/95 backdrop-blur-xl rounded-[24px] w-full max-w-lg max-h-[90vh] shadow-2xl animate-in zoom-in-95 duration-200 flex flex-col border border-white/20 dark:border-white/10">
          <div class="flex items-center justify-between p-6 border-b border-gray-100 dark:border-gray-700 shrink-0">
            <h3 class="text-lg font-bold text-gray-900 dark:text-white">通知设置</h3>
            <button class="p-2 hover:bg-gray-100 dark:hover:bg-gray-700 rounded-full transition" @click="showNotificationModal = false">
              <X :size="20" class="text-gray-500" />
            </button>
          </div>
          
          <div v-if="notificationLoading" class="p-10 text-center">
            <div class="animate-spin w-8 h-8 border-2 border-primary border-t-transparent rounded-full mx-auto"></div>
            <p class="text-gray-500 mt-4 text-sm">加载配置...</p>
          </div>
          
          <div v-else class="flex-1 overflow-y-auto p-6 space-y-6">
            <!-- Master Toggle -->
            <div class="flex items-center justify-between p-4 bg-gray-50 dark:bg-white/5 rounded-2xl">
              <div>
                <div class="font-medium text-gray-900 dark:text-white text-sm">启用通知</div>
                <div class="text-xs text-gray-500 mt-0.5">开启后将根据配置发送提醒</div>
              </div>
              <button 
                class="w-12 h-7 rounded-full transition-colors duration-200 relative"
                :class="notificationForm.enabled ? 'bg-primary' : 'bg-gray-300 dark:bg-gray-600'"
                @click="notificationForm.enabled = !notificationForm.enabled"
              >
                <div class="absolute top-1 w-5 h-5 bg-white rounded-full shadow-md transition-transform duration-200" :class="notificationForm.enabled ? 'translate-x-6' : 'translate-x-1'"></div>
              </button>
            </div>

            <!-- Channel Tabs -->
            <div class="flex gap-1 p-1 bg-gray-100 dark:bg-white/5 rounded-xl">
              <button 
                v-for="tab in [{id: 'wecom', label: '企业微信'}, {id: 'dingtalk', label: '钉钉'}, {id: 'email', label: '邮箱'}, {id: 'webhook', label: 'Webhook'}]"
                :key="tab.id"
                class="flex-1 py-2 text-xs font-medium rounded-lg transition-all"
                :class="activeNotifyTab === tab.id ? 'bg-white dark:bg-gray-600 text-gray-900 dark:text-white shadow-sm' : 'text-gray-500 hover:text-gray-700 dark:hover:text-gray-300'"
                @click="activeNotifyTab = tab.id as any"
              >
                {{ tab.label }}
              </button>
            </div>

            <!-- WeCom Config -->
            <div v-if="activeNotifyTab === 'wecom'" class="space-y-4">
              <div class="flex items-center justify-between">
                <span class="text-sm font-medium text-gray-700 dark:text-gray-300">启用企业微信</span>
                <button 
                  class="w-10 h-6 rounded-full transition-colors"
                  :class="notificationForm.wecom_enabled ? 'bg-primary' : 'bg-gray-300 dark:bg-gray-600'"
                  @click="notificationForm.wecom_enabled = !notificationForm.wecom_enabled"
                >
                  <div class="w-4 h-4 bg-white rounded-full shadow transition-transform" :class="notificationForm.wecom_enabled ? 'translate-x-5' : 'translate-x-1'"></div>
                </button>
              </div>
              <div class="space-y-1.5">
                <label class="text-xs font-bold text-gray-400 uppercase">Webhook 地址</label>
                <input v-model="notificationForm.wecom_webhook" type="text" placeholder="https://qyapi.weixin.qq.com/cgi-bin/webhook/send?key=xxx" class="w-full h-11 px-4 bg-gray-50 dark:bg-black/30 rounded-xl border-0 outline-none focus:ring-2 focus:ring-primary/20 text-sm text-gray-900 dark:text-white" />
              </div>
              <button class="w-full py-2.5 border border-gray-200 dark:border-gray-600 rounded-xl text-sm font-medium text-gray-600 dark:text-gray-300 hover:bg-gray-50 dark:hover:bg-gray-700 transition" :disabled="testingChannel === 'wecom'" @click="testNotification('wecom')">
                {{ testingChannel === 'wecom' ? '测试中...' : '发送测试消息' }}
              </button>
            </div>

            <!-- DingTalk Config -->
            <div v-if="activeNotifyTab === 'dingtalk'" class="space-y-4">
              <div class="flex items-center justify-between">
                <span class="text-sm font-medium text-gray-700 dark:text-gray-300">启用钉钉</span>
                <button 
                  class="w-10 h-6 rounded-full transition-colors"
                  :class="notificationForm.dingtalk_enabled ? 'bg-primary' : 'bg-gray-300 dark:bg-gray-600'"
                  @click="notificationForm.dingtalk_enabled = !notificationForm.dingtalk_enabled"
                >
                  <div class="w-4 h-4 bg-white rounded-full shadow transition-transform" :class="notificationForm.dingtalk_enabled ? 'translate-x-5' : 'translate-x-1'"></div>
                </button>
              </div>
              <div class="space-y-1.5">
                <label class="text-xs font-bold text-gray-400 uppercase">Webhook 地址</label>
                <input v-model="notificationForm.dingtalk_webhook" type="text" placeholder="https://oapi.dingtalk.com/robot/send?access_token=xxx" class="w-full h-11 px-4 bg-gray-50 dark:bg-black/30 rounded-xl border-0 outline-none focus:ring-2 focus:ring-primary/20 text-sm text-gray-900 dark:text-white" />
              </div>
              <div class="space-y-1.5">
                <label class="text-xs font-bold text-gray-400 uppercase">加签密钥（可选）</label>
                <input v-model="notificationForm.dingtalk_secret" type="text" placeholder="SEC..." class="w-full h-11 px-4 bg-gray-50 dark:bg-black/30 rounded-xl border-0 outline-none focus:ring-2 focus:ring-primary/20 text-sm text-gray-900 dark:text-white" />
              </div>
              <button class="w-full py-2.5 border border-gray-200 dark:border-gray-600 rounded-xl text-sm font-medium text-gray-600 dark:text-gray-300 hover:bg-gray-50 dark:hover:bg-gray-700 transition" :disabled="testingChannel === 'dingtalk'" @click="testNotification('dingtalk')">
                {{ testingChannel === 'dingtalk' ? '测试中...' : '发送测试消息' }}
              </button>
            </div>

            <!-- Email Config -->
            <div v-if="activeNotifyTab === 'email'" class="space-y-4">
              <div class="flex items-center justify-between">
                <span class="text-sm font-medium text-gray-700 dark:text-gray-300">启用邮箱</span>
                <button 
                  class="w-10 h-6 rounded-full transition-colors"
                  :class="notificationForm.email_enabled ? 'bg-primary' : 'bg-gray-300 dark:bg-gray-600'"
                  @click="notificationForm.email_enabled = !notificationForm.email_enabled"
                >
                  <div class="w-4 h-4 bg-white rounded-full shadow transition-transform" :class="notificationForm.email_enabled ? 'translate-x-5' : 'translate-x-1'"></div>
                </button>
              </div>
              <div class="grid grid-cols-2 gap-3">
                <div class="space-y-1.5">
                  <label class="text-xs font-bold text-gray-400 uppercase">SMTP 服务器</label>
                  <input v-model="notificationForm.smtp_host" type="text" placeholder="smtp.qq.com" class="w-full h-11 px-4 bg-gray-50 dark:bg-black/30 rounded-xl border-0 outline-none focus:ring-2 focus:ring-primary/20 text-sm text-gray-900 dark:text-white" />
                </div>
                <div class="space-y-1.5">
                  <label class="text-xs font-bold text-gray-400 uppercase">端口</label>
                  <input v-model.number="notificationForm.smtp_port" type="number" placeholder="587" class="w-full h-11 px-4 bg-gray-50 dark:bg-black/30 rounded-xl border-0 outline-none focus:ring-2 focus:ring-primary/20 text-sm text-gray-900 dark:text-white" />
                </div>
              </div>
              <div class="space-y-1.5">
                <label class="text-xs font-bold text-gray-400 uppercase">邮箱账号</label>
                <input v-model="notificationForm.smtp_user" type="text" placeholder="your@email.com" class="w-full h-11 px-4 bg-gray-50 dark:bg-black/30 rounded-xl border-0 outline-none focus:ring-2 focus:ring-primary/20 text-sm text-gray-900 dark:text-white" />
              </div>
              <div class="space-y-1.5">
                <label class="text-xs font-bold text-gray-400 uppercase">密码/授权码</label>
                <input v-model="notificationForm.smtp_password" type="password" placeholder="留空则使用已保存的密码" class="w-full h-11 px-4 bg-gray-50 dark:bg-black/30 rounded-xl border-0 outline-none focus:ring-2 focus:ring-primary/20 text-sm text-gray-900 dark:text-white" />
              </div>
              <div class="p-3 bg-blue-50 dark:bg-blue-900/20 rounded-xl">
                <p class="text-xs text-blue-600 dark:text-blue-400">
                  📧 邮件将发送至个人信息中设置的邮箱地址
                </p>
              </div>
              <button class="w-full py-2.5 border border-gray-200 dark:border-gray-600 rounded-xl text-sm font-medium text-gray-600 dark:text-gray-300 hover:bg-gray-50 dark:hover:bg-gray-700 transition" :disabled="testingChannel === 'email'" @click="testNotification('email')">
                {{ testingChannel === 'email' ? '测试中...' : '发送测试邮件' }}
              </button>
            </div>

            <!-- Webhook Config -->
            <div v-if="activeNotifyTab === 'webhook'" class="space-y-4">
              <div class="flex items-center justify-between">
                <span class="text-sm font-medium text-gray-700 dark:text-gray-300">启用 Webhook</span>
                <button 
                  class="w-10 h-6 rounded-full transition-colors"
                  :class="notificationForm.webhook_enabled ? 'bg-primary' : 'bg-gray-300 dark:bg-gray-600'"
                  @click="notificationForm.webhook_enabled = !notificationForm.webhook_enabled"
                >
                  <div class="w-4 h-4 bg-white rounded-full shadow transition-transform" :class="notificationForm.webhook_enabled ? 'translate-x-5' : 'translate-x-1'"></div>
                </button>
              </div>
              <div class="space-y-1.5">
                <label class="text-xs font-bold text-gray-400 uppercase">Webhook URL</label>
                <input v-model="notificationForm.webhook_url" type="text" placeholder="https://your-server.com/webhook" class="w-full h-11 px-4 bg-gray-50 dark:bg-black/30 rounded-xl border-0 outline-none focus:ring-2 focus:ring-primary/20 text-sm text-gray-900 dark:text-white" />
              </div>
              <div class="space-y-1.5">
                <label class="text-xs font-bold text-gray-400 uppercase">密钥（可选）</label>
                <input v-model="notificationForm.webhook_secret" type="text" placeholder="用于签名验证" class="w-full h-11 px-4 bg-gray-50 dark:bg-black/30 rounded-xl border-0 outline-none focus:ring-2 focus:ring-primary/20 text-sm text-gray-900 dark:text-white" />
              </div>
              <button class="w-full py-2.5 border border-gray-200 dark:border-gray-600 rounded-xl text-sm font-medium text-gray-600 dark:text-gray-300 hover:bg-gray-50 dark:hover:bg-gray-700 transition" :disabled="testingChannel === 'webhook'" @click="testNotification('webhook')">
                {{ testingChannel === 'webhook' ? '测试中...' : '发送测试请求' }}
              </button>
            </div>

            <!-- Notification Options -->
            <div class="pt-4 border-t border-gray-100 dark:border-gray-700 space-y-4">
              <h4 class="text-sm font-bold text-gray-500">通知选项</h4>
              <div class="flex items-center justify-between">
                <span class="text-sm text-gray-700 dark:text-gray-300">还款日提醒</span>
                <button 
                  class="w-10 h-6 rounded-full transition-colors"
                  :class="notificationForm.notify_payment_due ? 'bg-primary' : 'bg-gray-300 dark:bg-gray-600'"
                  @click="notificationForm.notify_payment_due = !notificationForm.notify_payment_due"
                >
                  <div class="w-4 h-4 bg-white rounded-full shadow transition-transform" :class="notificationForm.notify_payment_due ? 'translate-x-5' : 'translate-x-1'"></div>
                </button>
              </div>
              <div class="flex items-center justify-between">
                <span class="text-sm text-gray-700 dark:text-gray-300">预算超支提醒</span>
                <button 
                  class="w-10 h-6 rounded-full transition-colors"
                  :class="notificationForm.notify_budget_alert ? 'bg-primary' : 'bg-gray-300 dark:bg-gray-600'"
                  @click="notificationForm.notify_budget_alert = !notificationForm.notify_budget_alert"
                >
                  <div class="w-4 h-4 bg-white rounded-full shadow transition-transform" :class="notificationForm.notify_budget_alert ? 'translate-x-5' : 'translate-x-1'"></div>
                </button>
              </div>
              <div class="flex items-center justify-between">
                <span class="text-sm text-gray-700 dark:text-gray-300">借款到期提醒</span>
                <button 
                  class="w-10 h-6 rounded-full transition-colors"
                  :class="notificationForm.notify_lending_due ? 'bg-primary' : 'bg-gray-300 dark:bg-gray-600'"
                  @click="notificationForm.notify_lending_due = !notificationForm.notify_lending_due"
                >
                  <div class="w-4 h-4 bg-white rounded-full shadow transition-transform" :class="notificationForm.notify_lending_due ? 'translate-x-5' : 'translate-x-1'"></div>
                </button>
              </div>
                            <div class="flex items-center justify-between">
                <span class="text-sm text-gray-700 dark:text-gray-300">年度报告通知</span>
                <button 
                  class="w-10 h-6 rounded-full transition-colors"
                  :class="notificationForm.notify_annual_report ? 'bg-primary' : 'bg-gray-300 dark:bg-gray-600'"
                  @click="notificationForm.notify_annual_report = !notificationForm.notify_annual_report"
                >
                  <div class="w-4 h-4 bg-white rounded-full shadow transition-transform" :class="notificationForm.notify_annual_report ? 'translate-x-5' : 'translate-x-1'"></div>
                </button>
              </div>
              <div class="flex items-center justify-between">
                <span class="text-sm text-gray-700 dark:text-gray-300">提前提醒天数</span>
                <select v-model.number="notificationForm.advance_days" class="h-9 px-3 bg-gray-50 dark:bg-black/30 rounded-lg border-0 outline-none text-sm text-gray-900 dark:text-white">
                  <option :value="1">1 天</option>
                  <option :value="2">2 天</option>
                  <option :value="3">3 天</option>
                  <option :value="5">5 天</option>
                  <option :value="7">7 天</option>
                </select>
              </div>
            </div>
          </div>
          
          <div class="p-6 border-t border-gray-100 dark:border-gray-700 shrink-0">
            <button
              class="w-full h-12 bg-primary text-white rounded-xl font-bold hover:bg-primary/90 disabled:opacity-50 transition shadow-lg shadow-primary/20"
              :disabled="notificationLoading"
              @click="saveNotificationSettings"
            >
              {{ notificationLoading ? '保存中...' : '保存设置' }}
            </button>
          </div>
        </div>
      </div>
    </Teleport>

    <!-- Security Entry Path Modal -->
    <Teleport to="body">
      <div v-if="showSecurityModal" class="fixed inset-0 z-50 flex items-center justify-center p-4">
        <div class="absolute inset-0 bg-black/40 backdrop-blur-sm" @click="showSecurityModal = false"></div>
        <div class="relative bg-white/90 dark:bg-[#1C1C1E]/90 backdrop-blur-xl rounded-[24px] w-full max-w-md shadow-2xl animate-in zoom-in-95 duration-200 border border-white/20 dark:border-white/10">
          <div class="flex items-center justify-between p-6 border-b border-gray-100/50 dark:border-white/10">
            <h3 class="text-lg font-bold text-gray-900 dark:text-white">安全入口</h3>
            <button class="p-2 hover:bg-black/5 dark:hover:bg-white/10 rounded-full transition" @click="showSecurityModal = false">
              <X :size="20" class="text-gray-500" />
            </button>
          </div>
          
          <div class="p-6 space-y-6">
            <!-- Info Notice -->
            <div class="bg-amber-50 dark:bg-amber-900/20 rounded-xl p-4 border border-amber-100 dark:border-amber-900/30">
              <div class="flex gap-3">
                <Shield :size="18" class="text-amber-500 flex-shrink-0 mt-0.5" />
                <div class="text-sm text-amber-700 dark:text-amber-300">
                  <p class="font-medium mb-1">类似宝塔面板的安全入口</p>
                  <p class="text-xs opacity-90">
                    启用后，必须通过指定路径才能访问系统，直接访问根路径将返回 404。
                  </p>
                </div>
              </div>
            </div>

            <!-- Status -->
            <div class="flex items-center justify-between p-4 bg-gray-50 dark:bg-black/30 rounded-xl">
              <span class="text-sm text-gray-700 dark:text-gray-300">当前状态</span>
              <span v-if="entryPathEnabled" class="px-2 py-0.5 bg-green-100 dark:bg-green-900/30 text-green-600 dark:text-green-400 rounded text-xs font-medium">已启用</span>
              <span v-else class="px-2 py-0.5 bg-gray-100 dark:bg-gray-700 text-gray-500 rounded text-xs font-medium">未启用</span>
            </div>

            <!-- Entry Path Input -->
            <div>
              <label class="block text-sm font-medium text-gray-700 dark:text-gray-300 mb-2">入口路径</label>
              <div class="flex gap-2">
                <input
                  v-model="entryPath"
                  type="text"
                  placeholder="/your-secret-path"
                  class="flex-1 h-11 px-4 bg-gray-50 dark:bg-black/30 border border-gray-200 dark:border-gray-700 rounded-xl text-gray-900 dark:text-white placeholder:text-gray-400 focus:outline-none focus:ring-2 focus:ring-primary/50 font-mono text-sm"
                />
                <button
                  @click="generateEntryPath"
                  :disabled="entryPathLoading"
                  class="h-11 px-3 bg-gray-100 dark:bg-gray-800 text-gray-600 dark:text-gray-300 rounded-xl hover:bg-gray-200 dark:hover:bg-gray-700 transition"
                  title="生成随机路径"
                >
                  <RefreshCw :size="18" :class="{ 'animate-spin': entryPathLoading }" />
                </button>
              </div>
              <p class="text-xs text-gray-500 mt-2">以 / 开头，例如: /my-secret-2024</p>
            </div>

            <!-- Current URL Preview -->
            <div v-if="entryPath" class="p-4 bg-blue-50 dark:bg-blue-900/20 rounded-xl">
              <p class="text-xs text-blue-600 dark:text-blue-400 mb-2">完整访问地址:</p>
              <div class="flex items-center gap-2">
                <code class="flex-1 text-xs font-mono text-blue-700 dark:text-blue-300 break-all">
                  {{ entryFullUrl }}
                </code>
                <button
                  @click="copyEntryUrl"
                  class="p-2 hover:bg-blue-100 dark:hover:bg-blue-800/30 rounded-lg transition"
                  title="复制"
                >
                  <Copy :size="16" class="text-blue-500" />
                </button>
              </div>
            </div>
          </div>
          
          <div class="p-6 border-t border-gray-100 dark:border-gray-700 space-y-3">
            <button
              class="w-full h-11 bg-primary text-white rounded-xl font-medium hover:bg-primary/90 disabled:opacity-50 transition"
              :disabled="entryPathLoading"
              @click="saveEntryPath"
            >
              {{ entryPathLoading ? '保存中...' : '保存设置' }}
            </button>
            <button
              v-if="entryPathEnabled"
              class="w-full h-11 bg-red-50 dark:bg-red-900/20 text-red-600 dark:text-red-400 rounded-xl font-medium hover:bg-red-100 dark:hover:bg-red-900/30 transition"
              :disabled="entryPathLoading"
              @click="disableEntryPath"
            >
              禁用安全入口
            </button>
          </div>
        </div>
      </div>
    </Teleport>

    <!-- API Token Modal -->
    <Teleport to="body">
      <div v-if="showApiTokenModal" class="fixed inset-0 z-50 flex items-center justify-center p-4">
        <div class="absolute inset-0 bg-black/40 backdrop-blur-sm" @click="showApiTokenModal = false"></div>
        <div class="relative bg-white/90 dark:bg-[#1C1C1E]/90 backdrop-blur-xl rounded-[24px] w-full max-w-md shadow-2xl animate-in zoom-in-95 duration-200 border border-white/20 dark:border-white/10 max-h-[90vh] flex flex-col">
          <div class="flex items-center justify-between p-6 border-b border-gray-100/50 dark:border-white/10 shrink-0">
            <h3 class="text-lg font-bold text-gray-900 dark:text-white">API Token 管理</h3>
            <button class="p-2 hover:bg-black/5 dark:hover:bg-white/10 rounded-full transition" @click="showApiTokenModal = false">
              <X :size="20" class="text-gray-500" />
            </button>
          </div>
          
          <div class="p-6 space-y-6 overflow-y-auto">
            <!-- Info -->
            <div class="bg-cyan-50 dark:bg-cyan-900/20 rounded-xl p-4 border border-cyan-100 dark:border-cyan-900/30">
              <div class="flex gap-3">
                <Key :size="18" class="text-cyan-500 flex-shrink-0 mt-0.5" />
                <div class="text-sm text-cyan-700 dark:text-cyan-300">
                  <p class="font-medium mb-1">用于 App 或 API 访问</p>
                  <p class="text-xs opacity-90">
                    创建令牌后，可在手机 App 中使用此令牌进行身份验证，无需每次输入密码。
                  </p>
                </div>
              </div>
            </div>

            <!-- Create New Token -->
            <div class="space-y-3">
              <h4 class="text-sm font-bold text-gray-500">创建新令牌</h4>
              <div class="flex gap-2">
                <input
                  v-model="newTokenName"
                  type="text"
                  placeholder="令牌名称（如：我的手机）"
                  class="flex-1 h-11 px-4 bg-gray-50 dark:bg-black/30 rounded-xl border-0 outline-none focus:ring-2 focus:ring-primary/20 transition-all text-sm text-gray-900 dark:text-white placeholder:text-gray-400"
                />
                <select v-model.number="newTokenExpiry" class="h-11 px-3 bg-gray-50 dark:bg-black/30 rounded-xl border-0 outline-none text-sm text-gray-900 dark:text-white">
                  <option :value="0">永不过期</option>
                  <option :value="30">30 天</option>
                  <option :value="90">90 天</option>
                  <option :value="365">1 年</option>
                </select>
              </div>
              <button
                class="w-full h-11 bg-primary text-white rounded-xl font-medium hover:bg-primary/90 disabled:opacity-50 transition flex items-center justify-center gap-2"
                :disabled="apiTokenLoading || !newTokenName.trim()"
                @click="createApiToken"
              >
                <Plus :size="18" />
                创建令牌
              </button>
            </div>

            <!-- Created Token (show once) -->
            <div v-if="createdToken" class="bg-green-50 dark:bg-green-900/20 rounded-xl p-4 border border-green-200 dark:border-green-900/30">
              <div class="flex items-center gap-2 mb-2">
                <Check :size="18" class="text-green-500" />
                <span class="text-sm font-bold text-green-700 dark:text-green-300">令牌创建成功！</span>
              </div>
              <p class="text-xs text-green-600 dark:text-green-400 mb-3">请立即复制并保存，此令牌只显示一次：</p>
              <div class="flex items-center gap-2">
                <code class="flex-1 text-xs font-mono text-green-700 dark:text-green-300 bg-green-100 dark:bg-green-900/30 p-2 rounded-lg break-all">
                  {{ createdToken }}
                </code>
                <button
                  @click="copyToken(createdToken)"
                  class="p-2 hover:bg-green-100 dark:hover:bg-green-800/30 rounded-lg transition"
                  title="复制"
                >
                  <Copy :size="16" class="text-green-500" />
                </button>
              </div>
            </div>

            <!-- Token List -->
            <div class="space-y-3">
              <h4 class="text-sm font-bold text-gray-500">已创建的令牌</h4>
              <div v-if="apiTokenLoading" class="text-center py-4">
                <div class="animate-spin w-6 h-6 border-2 border-primary border-t-transparent rounded-full mx-auto"></div>
              </div>
              <div v-else-if="apiTokens.length === 0" class="text-center py-6 text-gray-400 text-sm">
                暂无令牌
              </div>
              <div v-else class="space-y-2">
                <div v-for="token in apiTokens" :key="token.id" class="flex items-center gap-3 p-3 bg-gray-50 dark:bg-black/20 rounded-xl">
                  <div class="w-10 h-10 rounded-full bg-cyan-100 dark:bg-cyan-900/30 flex items-center justify-center">
                    <Smartphone :size="18" class="text-cyan-500" />
                  </div>
                  <div class="flex-1 min-w-0">
                    <p class="font-medium text-sm text-gray-900 dark:text-white truncate">{{ token.name }}</p>
                    <p class="text-xs text-gray-500">
                      <span class="font-mono">{{ token.token_prefix }}...</span>
                      <span v-if="token.last_used_at" class="ml-2">最后使用: {{ dayjs(token.last_used_at).format('MM-DD HH:mm') }}</span>
                      <span v-if="token.expires_at" class="ml-2 text-orange-500">{{ dayjs(token.expires_at).format('YYYY-MM-DD') }} 过期</span>
                    </p>
                  </div>
                  <button
                    @click="deleteApiToken(token.id)"
                    class="p-2 hover:bg-red-100 dark:hover:bg-red-900/30 rounded-lg transition"
                    title="删除"
                  >
                    <Trash2 :size="16" class="text-red-500" />
                  </button>
                </div>
              </div>
            </div>
          </div>
        </div>
      </div>
    </Teleport>

    <!-- Profile Edit Modal -->
    <Teleport to="body">
      <div v-if="showProfileModal" class="fixed inset-0 z-50 flex items-center justify-center p-4">
        <div class="absolute inset-0 bg-black/40 backdrop-blur-sm" @click="showProfileModal = false"></div>
        <div class="relative bg-white/90 dark:bg-[#1C1C1E]/90 backdrop-blur-xl rounded-[24px] w-full max-w-sm shadow-2xl animate-in zoom-in-95 duration-200 border border-white/20 dark:border-white/10">
          <div class="flex items-center justify-between p-6 border-b border-gray-100/50 dark:border-white/10">
            <h3 class="text-lg font-bold text-gray-900 dark:text-white">编辑个人信息</h3>
            <button class="p-2 hover:bg-black/5 dark:hover:bg-white/10 rounded-full transition" @click="showProfileModal = false">
              <X :size="20" class="text-gray-500" />
            </button>
          </div>
          
          <div v-if="profileLoading" class="p-10 text-center">
            <div class="animate-spin w-8 h-8 border-2 border-primary border-t-transparent rounded-full mx-auto"></div>
            <p class="text-gray-500 mt-4 text-sm">加载中...</p>
          </div>
          
          <div v-else class="p-6 space-y-4">
            <div class="space-y-1.5">
              <label class="text-xs font-bold text-gray-400 uppercase tracking-wider">昵称</label>
              <input
                v-model="profileForm.nickname"
                type="text"
                placeholder="输入昵称"
                class="w-full h-12 px-4 bg-gray-50 dark:bg-black/30 rounded-xl border-0 outline-none focus:ring-2 focus:ring-primary/20 transition-all font-medium text-gray-900 dark:text-white placeholder:text-gray-400"
              />
            </div>
            <div class="space-y-1.5">
              <label class="text-xs font-bold text-gray-400 uppercase tracking-wider">邮箱</label>
              <input
                v-model="profileForm.email"
                type="email"
                placeholder="your@email.com"
                class="w-full h-12 px-4 bg-gray-50 dark:bg-black/30 rounded-xl border-0 outline-none focus:ring-2 focus:ring-primary/20 transition-all font-medium text-gray-900 dark:text-white placeholder:text-gray-400"
              />
            </div>
            <div class="space-y-1.5">
              <label class="text-xs font-bold text-gray-400 uppercase tracking-wider">头像</label>
              <div class="flex items-center gap-4">
                <div class="w-16 h-16 rounded-full bg-gradient-to-br from-gray-100 to-gray-200 dark:from-gray-700 dark:to-gray-800 flex items-center justify-center overflow-hidden border border-white/20">
                  <img v-if="profileForm.avatar" :src="profileForm.avatar" class="w-full h-full object-cover" />
                  <User v-else class="text-gray-400" :size="28" />
                </div>
                <label class="flex-1">
                  <div 
                    class="h-12 px-4 bg-gray-50 dark:bg-black/30 rounded-xl flex items-center justify-center cursor-pointer hover:bg-gray-100 dark:hover:bg-black/50 transition text-sm text-gray-500"
                    :class="{ 'opacity-50': avatarUploading }"
                  >
                    {{ avatarUploading ? '上传中...' : '点击上传头像' }}
                  </div>
                  <input type="file" accept="image/*" class="hidden" :disabled="avatarUploading" @change="handleAvatarUpload" />
                </label>
              </div>
            </div>
            <div class="space-y-1.5">
              <label class="text-xs font-bold text-gray-400 uppercase tracking-wider">个性签名</label>
              <input
                v-model="profileForm.bio"
                type="text"
                placeholder="一句话介绍自己"
                maxlength="50"
                class="w-full h-12 px-4 bg-gray-50 dark:bg-black/30 rounded-xl border-0 outline-none focus:ring-2 focus:ring-primary/20 transition-all font-medium text-gray-900 dark:text-white placeholder:text-gray-400"
              />
            </div>

            <button
              class="w-full h-12 bg-primary text-white rounded-xl font-bold hover:bg-primary/90 disabled:opacity-50 disabled:cursor-not-allowed transition shadow-lg shadow-primary/20 mt-2"
              :disabled="profileLoading"
              @click="saveProfile"
            >
              {{ profileLoading ? '保存中...' : '保存' }}
            </button>
          </div>
        </div>
      </div>
    </Teleport>

    <!-- Auto Backup Modal -->
    <Teleport to="body">
      <div v-if="showAutoBackupModal" class="fixed inset-0 z-50 flex items-center justify-center p-4">
        <div class="absolute inset-0 bg-black/40 backdrop-blur-sm" @click="showAutoBackupModal = false"></div>
        <div class="relative bg-white/90 dark:bg-[#1C1C1E]/90 backdrop-blur-xl rounded-[24px] w-full max-w-md shadow-2xl animate-in zoom-in-95 duration-200 border border-white/20 dark:border-white/10 max-h-[85vh] overflow-hidden flex flex-col">
          <div class="flex items-center justify-between p-6 border-b border-gray-100/50 dark:border-white/10">
            <h3 class="text-lg font-bold text-gray-900 dark:text-white">自动备份设置</h3>
            <button class="p-2 hover:bg-black/5 dark:hover:bg-white/10 rounded-full transition" @click="showAutoBackupModal = false">
              <X :size="20" class="text-gray-500" />
            </button>
          </div>
          
          <div v-if="autoBackupLoading" class="p-10 text-center">
            <div class="animate-spin w-8 h-8 border-2 border-primary border-t-transparent rounded-full mx-auto"></div>
            <p class="text-gray-500 mt-4 text-sm">加载中...</p>
          </div>
          
          <div v-else class="p-6 space-y-5 overflow-y-auto flex-1">
            <!-- Enable toggle -->
            <div class="flex items-center justify-between">
              <div>
                <span class="text-sm font-medium text-gray-900 dark:text-white">启用自动备份</span>
                <p class="text-xs text-gray-500 mt-0.5">定时自动备份数据到服务器</p>
              </div>
              <button 
                class="w-12 h-7 rounded-full transition-colors"
                :class="autoBackupForm.enabled ? 'bg-primary' : 'bg-gray-300 dark:bg-gray-600'"
                @click="autoBackupForm.enabled = !autoBackupForm.enabled"
              >
                <div class="w-5 h-5 bg-white rounded-full shadow transition-transform" :class="autoBackupForm.enabled ? 'translate-x-6' : 'translate-x-1'"></div>
              </button>
            </div>

            <!-- Frequency -->
            <div class="space-y-2">
              <label class="text-xs font-bold text-gray-400 uppercase tracking-wider">备份周期</label>
              <div class="grid grid-cols-3 gap-2">
                <button 
                  v-for="opt in [{value: 'daily', label: '每天'}, {value: 'weekly', label: '每周'}, {value: 'monthly', label: '每月'}]"
                  :key="opt.value"
                  class="py-2.5 rounded-xl text-sm font-medium transition"
                  :class="autoBackupForm.frequency === opt.value ? 'bg-primary text-white' : 'bg-gray-100 dark:bg-gray-800 text-gray-600 dark:text-gray-300'"
                  @click="autoBackupForm.frequency = opt.value"
                >
                  {{ opt.label }}
                </button>
              </div>
            </div>

            <!-- Hour -->
            <div class="space-y-2">
              <label class="text-xs font-bold text-gray-400 uppercase tracking-wider">备份时间</label>
              <select 
                v-model="autoBackupForm.hour" 
                class="w-full h-12 px-4 bg-gray-50 dark:bg-black/30 rounded-xl border-0 outline-none text-gray-900 dark:text-white"
              >
                <option v-for="h in 24" :key="h-1" :value="h-1">{{ String(h-1).padStart(2, '0') }}:00</option>
              </select>
            </div>

            <!-- Max backups -->
            <div class="space-y-2">
              <label class="text-xs font-bold text-gray-400 uppercase tracking-wider">保留备份数量</label>
              <select 
                v-model="autoBackupForm.max_backups" 
                class="w-full h-12 px-4 bg-gray-50 dark:bg-black/30 rounded-xl border-0 outline-none text-gray-900 dark:text-white"
              >
                <option v-for="n in [5, 10, 20, 30, 50]" :key="n" :value="n">最多保留 {{ n }} 份</option>
              </select>
            </div>

            <!-- Backup list -->
            <div v-if="autoBackupFiles.length > 0" class="space-y-2">
              <label class="text-xs font-bold text-gray-400 uppercase tracking-wider">已有备份 ({{ autoBackupFiles.length }})</label>
              <div class="max-h-32 overflow-y-auto space-y-1">
                <div 
                  v-for="file in autoBackupFiles" 
                  :key="file.filename"
                  class="flex items-center justify-between p-2 bg-gray-50 dark:bg-black/30 rounded-lg text-xs"
                >
                  <span class="text-gray-600 dark:text-gray-400 truncate flex-1">{{ file.filename }}</span>
                  <span class="text-gray-400 ml-2">{{ formatFileSize(file.size) }}</span>
                </div>
              </div>
            </div>

            <!-- Actions -->
            <div class="flex gap-3 pt-2">
              <button
                class="flex-1 py-3 bg-gray-100 dark:bg-gray-800 text-gray-700 dark:text-gray-300 rounded-xl font-medium hover:bg-gray-200 dark:hover:bg-gray-700 transition"
                :disabled="autoBackupLoading"
                @click="triggerAutoBackup"
              >
                立即备份
              </button>
              <button
                class="flex-1 py-3 bg-primary text-white rounded-xl font-medium hover:bg-primary/90 transition shadow-lg shadow-primary/20"
                :disabled="autoBackupLoading"
                @click="saveAutoBackupSettings"
              >
                保存设置
              </button>
            </div>
          </div>
        </div>
      </div>
    </Teleport>

  </div>
</template>
