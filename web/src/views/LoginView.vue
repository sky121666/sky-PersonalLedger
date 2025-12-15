<script setup lang="ts">
import { ref, onMounted } from 'vue'
import { useRouter } from 'vue-router'
import { useAuthStore } from '@/stores/auth'
import { Wallet, Shield, Database, Smartphone, ArrowRight, Lock, Eye, EyeOff } from 'lucide-vue-next'
import { toast } from '@/composables/useToast'

const router = useRouter()
const authStore = useAuthStore()

const password = ref('')
const confirmPassword = ref('')
const loading = ref(false)
const isInit = ref(false)
const showPassword = ref(false)
const showConfirmPassword = ref(false)

onMounted(async () => {
  await authStore.checkAuth()
  isInit.value = authStore.initialized === false
})

async function handleSubmit() {
  if (password.value.length < 6) {
    toast.warning('密码至少需要6位')
    return
  }

  if (isInit.value && password.value !== confirmPassword.value) {
    toast.warning('两次输入的密码不一致')
    return
  }

  loading.value = true
  try {
    if (isInit.value) {
      await authStore.init(password.value)
      toast.success('初始化成功')
    } else {
      await authStore.login(password.value)
      toast.success('欢迎回来')
    }
    router.replace('/')
  } catch (e: any) {
    toast.error(e.message || '操作失败，请重试')
    password.value = '' // Clear password on error
  } finally {
    loading.value = false
  }
}

const features = [
  { icon: Shield, title: '安全私密', desc: '数据存储在您的服务器，完全自主掌控' },
  { icon: Database, title: '私有部署', desc: '支持局域网或公网部署，数据不经第三方' },
  { icon: Smartphone, title: '多端访问', desc: 'Web端与移动App，随时随地管理账目' }
]
</script>

<template>
  <div class="min-h-screen bg-gray-50 dark:bg-gray-900 flex flex-col lg:flex-row">
    <!-- Left Side - Hero/Features (PC) -->
    <div class="hidden lg:flex flex-1 bg-white dark:bg-gray-800 relative overflow-hidden flex-col justify-center px-20 xl:px-32">
      <!-- Decorative Background -->
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

    <!-- Right Side - Login Form -->
    <div class="flex-1 flex items-center justify-center p-6 bg-gray-50 dark:bg-gray-900">
      <div class="w-full max-w-md bg-white/60 dark:bg-gray-800/60 backdrop-blur-2xl rounded-3xl p-8 shadow-[0_8px_30px_rgb(0,0,0,0.04)] border border-white/20 dark:border-gray-700/50">
        <!-- Mobile Logo -->
        <div class="lg:hidden text-center mb-8">
          <div class="w-16 h-16 bg-gradient-to-br from-primary to-blue-600 rounded-2xl flex items-center justify-center mx-auto mb-4 shadow-lg shadow-primary/20">
            <Wallet class="text-white" :size="32" />
          </div>
          <h1 class="text-2xl font-bold text-gray-900 dark:text-white">Personal Ledger</h1>
        </div>

        <div class="text-center mb-8">
          <h2 class="text-2xl font-bold text-gray-900 dark:text-white mb-2">{{ isInit ? '设置访问密码' : '欢迎回来' }}</h2>
          <p class="text-gray-500 dark:text-gray-400">{{ isInit ? '为了您的数据安全，请设置一个访问密码' : '请输入密码解锁您的账本' }}</p>
        </div>

        <div class="space-y-5">
          <div class="space-y-1.5">
            <label class="text-xs font-bold text-gray-400 uppercase tracking-wider ml-1">密码</label>
            <div class="relative">
              <div class="absolute left-4 top-1/2 -translate-y-1/2 text-gray-400">
                <Lock :size="20" />
              </div>
              <input
                v-model="password"
                :type="showPassword ? 'text' : 'password'"
                placeholder="请输入密码"
                class="w-full h-12 pl-11 pr-12 bg-white/50 dark:bg-gray-700/50 rounded-xl border border-gray-200/50 dark:border-gray-600/50 outline-none focus:ring-2 focus:ring-primary/20 focus:border-primary/50 transition-all font-medium dark:text-white"
                @keyup.enter="handleSubmit"
                autocomplete="current-password"
              />
              <button
                type="button"
                class="absolute right-4 top-1/2 -translate-y-1/2 text-gray-400 hover:text-gray-600 dark:hover:text-gray-300 transition-colors"
                @click="showPassword = !showPassword"
              >
                <Eye v-if="showPassword" :size="20" />
                <EyeOff v-else :size="20" />
              </button>
            </div>
          </div>

          <div v-if="isInit" class="space-y-1.5 animate-in slide-in-from-top-2">
            <label class="text-xs font-bold text-gray-400 uppercase tracking-wider ml-1">确认密码</label>
            <div class="relative">
              <div class="absolute left-4 top-1/2 -translate-y-1/2 text-gray-400">
                <Lock :size="20" />
              </div>
              <input
                v-model="confirmPassword"
                :type="showConfirmPassword ? 'text' : 'password'"
                placeholder="请再次输入密码"
                class="w-full h-12 pl-11 pr-12 bg-white/50 dark:bg-gray-700/50 rounded-xl border border-gray-200/50 dark:border-gray-600/50 outline-none focus:ring-2 focus:ring-primary/20 focus:border-primary/50 transition-all font-medium dark:text-white"
                @keyup.enter="handleSubmit"
                autocomplete="new-password"
              />
              <button
                type="button"
                class="absolute right-4 top-1/2 -translate-y-1/2 text-gray-400 hover:text-gray-600 dark:hover:text-gray-300 transition-colors"
                @click="showConfirmPassword = !showConfirmPassword"
              >
                <Eye v-if="showConfirmPassword" :size="20" />
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
            <span v-else>{{ isInit ? '开始使用' : '解锁' }}</span>
            <ArrowRight v-if="!loading" :size="20" class="group-hover:translate-x-1 transition-transform" />
          </button>
        </div>

        <p class="mt-8 text-center text-xs text-gray-400">
          <Shield :size="12" class="inline-block mr-1 align-text-bottom" />
          数据本地加密存储，安全无忧
        </p>
      </div>
    </div>
  </div>
</template>
