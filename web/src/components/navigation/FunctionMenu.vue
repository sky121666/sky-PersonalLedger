<script setup lang="ts">
import { onMounted, ref } from 'vue'
import { Pin, PinOff, X } from '@lucide/vue'
import { useRouter } from 'vue-router'
import { getNavigationItems, type NavigationId } from './catalog'
import { navigationIcons } from './icons'

defineProps<{ pinned: NavigationId[]; activeId: NavigationId | null; canCustomize: boolean }>()
const emit = defineEmits<{ navigate: [id: NavigationId]; pin: [id: NavigationId]; close: [] }>()
const router = useRouter()
const panel = ref<HTMLElement | null>(null)
const items = getNavigationItems().filter(item => item.path !== null)
onMounted(() => panel.value?.querySelector('a')?.focus())

function handleLink(event: MouseEvent, id: NavigationId) {
  if (event.button !== 0 || event.metaKey || event.ctrlKey || event.shiftKey || event.altKey) return
  event.preventDefault()
  emit('navigate', id)
}
</script>

<template>
  <div class="workspace-function-layer">
    <div class="workspace-function-backdrop" aria-hidden="true" @click="emit('close')"></div>
    <section id="workspace-functions" ref="panel" role="region" aria-label="更多功能" class="workspace-functions workspace-glass">
      <div class="workspace-functions-heading"><h2>所有功能</h2><button type="button" class="workspace-icon-button" aria-label="关闭更多导航" @click="emit('close')"><X :size="19" aria-hidden="true" /></button></div>
      <div class="workspace-function-list">
        <div v-for="item in items" :key="item.id" class="workspace-function-row">
          <a :href="router.resolve(item.path!).href" class="workspace-function-link" :aria-current="activeId === item.id ? 'page' : undefined" @click="handleLink($event, item.id)">
            <span class="workspace-function-icon"><component :is="navigationIcons[item.id]" :size="20" aria-hidden="true" /></span><span>{{ item.label }}</span>
          </a>
          <button
            v-if="item.canUnpin" type="button" class="workspace-icon-button workspace-pin"
            :disabled="!canCustomize" :aria-pressed="pinned.includes(item.id)"
            :aria-label="`${pinned.includes(item.id) ? '取消钉住' : '钉住'}${item.label}`"
            :title="pinned.includes(item.id) ? '取消钉住' : '钉住到导航'"
            @click="emit('pin', item.id)"
          ><component :is="pinned.includes(item.id) ? PinOff : Pin" :size="17" aria-hidden="true" /></button>
        </div>
      </div>
      <p v-if="!canCustomize" class="workspace-preference-note">暂时使用默认导航，请重试加载偏好。</p>
    </section>
  </div>
</template>
