<script setup lang="ts">
import { onMounted } from 'vue'
import { useRouter } from 'vue-router'
import { useAuthStore } from '@/stores/auth'
import Toast from '@/components/Toast.vue'

const router = useRouter()
const authStore = useAuthStore()

onMounted(async () => {
  await authStore.checkAuth()
  if (!authStore.isLoggedIn) {
    router.replace('/login')
  }
})
</script>

<template>
  <router-view />
  <Toast />
</template>

<style>
#app {
  width: 100%;
  height: 100%;
}
</style>
