<script setup lang="ts">
import { onMounted, ref } from 'vue'
import { useRoute, useRouter } from 'vue-router'
import { useAuthStore } from '@/stores/auth'
import { Wallet, Shield, Database, Smartphone, ArrowRight, Lock, Eye, EyeOff } from 'lucide-vue-next'
import { toast } from '@/composables/useToast'

const router = useRouter()
const route = useRoute()
const authStore = useAuthStore()

const password = ref('')
const loading = ref(false)
const showPassword = ref(false)

onMounted(async () => {
  await authStore.checkAuth()
  if (authStore.initialized === false) {
    router.replace('/setup')
    return
  }

  if (route.query.reason === 'expired') {
    toast.warning('登录已过期，请重新登录')
  }
})

async function handleSubmit() {
  if (!password.value) {
    toast.warning('请输入密码')
    return
  }

  loading.value = true
  try {
    await authStore.login(password.value)
    toast.success('欢迎回来')
    router.replace('/')
  } catch (e: any) {
    toast.error(e.message || '登录失败，请重试')
    password.value = ''
  } finally {
    loading.value = false
  }
}

const features = [
  { icon: Shield, title: '安全私密', desc: '数据存储在您的服务器，完全自主掌控' },
  { icon: Database, title: '灵活数据库', desc: '默认 SQLite，也可配置 PostgreSQL/MySQL' },
  { icon: Smartphone, title: '多端访问', desc: 'Web端与移动App，随时随地管理账目' }
]
</script>

<template>
  <div class="min-h-screen bg-gray-50 dark:bg-gray-900 flex flex-col lg:flex-row">
    <div class="hidden lg:flex flex-1 bg-white dark:bg-gray-800 relative overflow-hidden flex-col justify-center px-20 xl:px-32">
      <div class="absolute top-0 right-0 w-[600px] h-[600px] bg-primary/5 rounded-full blur-3xl -translate-y-1/2 translate-x-1/2"></div>
      <div class="absolute bottom-0 left-0 w-[400px] h-[400px] bg-blue-50 rounded-full blur-3xl translate-y-1/3 -translate-x-1/3"></div>

      <div class="relative z-10 max-w-lg">
        <div class="w-16 h-16 bg-gradient-to-br from-primary to-blue-600 rounded-2xl flex items-center justify-center shadow-lg shadow-primary/20 mb-8">
          <Wallet class="text-white" :size="32" />
        </div>

        <h1 class="text-4xl font-bold text-gray-900 dark:text-white mb-4 tracking-tight">
          Personal Ledger
        </h1>
        <p class="text-xl text-gray-500 dark:text-gray-400 mb-12 leading-relaxed">
          简单、优雅、安全的个人记账助手。<br>
          让每一笔收支都清晰可见。
        </p>

        <div class="space-y-8">
          <div v-for="(f, i) in features" :key="i" class="flex items-start gap-5 group">
            <div class="w-12 h-12 bg-white dark:bg-gray-700 rounded-2xl flex items-center justify-center shadow-sm border border-gray-100 dark:border-gray-600 group-hover:scale-110 transition-transform duration-300">
              <component :is="f.icon" class="text-primary" :size="24" />
            </div>
            <div>
              <h3 class="font-bold text-gray-900 dark:text-white text-lg mb-1">{{ f.title }}</h3>
              <p class="text-gray-500 dark:text-gray-400">{{ f.desc }}</p>
            </div>
          </div>
        </div>
      </div>
    </div>

    <div class="flex-1 flex items-center justify-center p-6 bg-gray-50 dark:bg-gray-900">
      <div class="w-full max-w-md bg-white/60 dark:bg-gray-800/60 backdrop-blur-2xl rounded-3xl p-8 shadow-[0_8px_30px_rgb(0,0,0,0.04)] border border-white/20 dark:border-gray-700/50">
        <div class="lg:hidden text-center mb-8">
          <div class="w-16 h-16 bg-gradient-to-br from-primary to-blue-600 rounded-2xl flex items-center justify-center mx-auto mb-4 shadow-lg shadow-primary/20">
            <Wallet class="text-white" :size="32" />
          </div>
          <h1 class="text-2xl font-bold text-gray-900 dark:text-white">Personal Ledger</h1>
        </div>

        <div class="text-center mb-8">
          <h2 class="text-2xl font-bold text-gray-900 dark:text-white mb-2">欢迎回来</h2>
          <p class="text-gray-500 dark:text-gray-400">请输入密码解锁您的账本</p>
        </div>

        <div class="space-y-5">
          <div class="space-y-1.5">
            <label for="login-password" class="text-xs font-bold text-gray-400 uppercase tracking-wider ml-1">密码</label>
            <div class="relative">
              <div class="absolute left-4 top-1/2 -translate-y-1/2 text-gray-400">
                <Lock :size="20" />
              </div>
              <input
                id="login-password"
                v-model="password"
                :type="showPassword ? 'text' : 'password'"
                placeholder="请输入密码"
                class="w-full h-12 pl-11 pr-12 bg-white/50 dark:bg-gray-700/50 rounded-xl border border-gray-200/50 dark:border-gray-600/50 outline-none focus:ring-2 focus:ring-primary/20 focus:border-primary/50 transition-all font-medium dark:text-white"
                :disabled="loading"
                autocomplete="current-password"
                @keyup.enter="handleSubmit"
              />
              <button
                type="button"
                :aria-label="showPassword ? '隐藏密码' : '显示密码'"
                :aria-pressed="showPassword"
                class="absolute right-4 top-1/2 -translate-y-1/2 text-gray-400 hover:text-gray-600 dark:hover:text-gray-300 transition-colors"
                @click="showPassword = !showPassword"
              >
                <Eye v-if="showPassword" :size="20" />
                <EyeOff v-else :size="20" />
              </button>
            </div>
          </div>

          <button
            :disabled="loading"
            class="w-full h-12 bg-primary text-white rounded-xl font-bold text-base hover:bg-primary/90 disabled:opacity-50 disabled:cursor-not-allowed transition-all shadow-lg shadow-primary/25 flex items-center justify-center gap-2 mt-4 group"
            @click="handleSubmit"
          >
            <span v-if="loading">验证中...</span>
            <span v-else>解锁</span>
            <ArrowRight v-if="!loading" :size="20" class="group-hover:translate-x-1 transition-transform" />
          </button>
        </div>

        <p class="mt-8 text-center text-xs text-gray-400">
          <Shield :size="12" class="inline-block mr-1 align-text-bottom" />
          数据由你自行托管，敏感凭据加密保存
        </p>
      </div>
    </div>
  </div>
</template>
