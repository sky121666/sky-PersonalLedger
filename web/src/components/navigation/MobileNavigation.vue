<script setup lang="ts">
import { computed } from 'vue'
import { Ellipsis } from '@lucide/vue'
import { getNavigationItem, type NavigationId } from './catalog'
import { navigationIcons } from './icons'

const props = defineProps<{ pinned: NavigationId[]; activeId: NavigationId | null; menuOpen: boolean }>()
const emit = defineEmits<{ navigate: [id: NavigationId]; more: [event: MouseEvent] }>()
const items = computed(() => props.pinned.filter(id => id !== 'more').slice(0, 4).map(getNavigationItem))
const activeInMore = computed(() => props.activeId !== null && !items.value.some(item => item.id === props.activeId))
</script>

<template>
  <nav aria-label="主导航" data-projection="mobile" class="workspace-mobile-nav workspace-glass">
    <button v-for="item in items" :key="item.id" type="button" class="workspace-destination" :aria-current="activeId === item.id ? 'page' : undefined" @click="emit('navigate', item.id)">
      <component :is="navigationIcons[item.id]" :size="22" aria-hidden="true" /><span>{{ item.label }}</span>
    </button>
    <button type="button" class="workspace-destination" :class="{ 'is-active': activeInMore }" aria-label="更多导航" :aria-expanded="menuOpen" aria-controls="workspace-functions" @click="emit('more', $event)">
      <Ellipsis :size="23" aria-hidden="true" /><span>更多</span>
    </button>
  </nav>
</template>
