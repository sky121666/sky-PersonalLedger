<script setup lang="ts">
import { computed, ref } from 'vue'
import { Wallet, PanelTop, PanelLeftClose, PanelLeftOpen, Plus, Sun, Moon, User, Ellipsis } from '@lucide/vue'
import { getNavigationItem, type NavigationId } from './catalog'
import { navigationIcons } from './icons'

const props = defineProps<{ pinned: NavigationId[]; activeId: NavigationId | null; dark: boolean; menuOpen: boolean; canCustomize: boolean }>()
const emit = defineEmits<{
  navigate: [id: NavigationId]
  more: [event: MouseEvent]
  mode: []
  quickAdd: []
  theme: []
}>()
const expanded = ref(false)
const items = computed(() => props.pinned.filter(id => !['more', 'settings'].includes(id)).map(getNavigationItem))
</script>

<template>
  <aside aria-label="钉住侧栏" class="workspace-rail workspace-glass" :class="{ 'is-expanded': expanded }">
    <div class="workspace-rail-brand"><span class="workspace-brand-icon"><Wallet :size="20" aria-hidden="true" /></span><span v-if="expanded">Personal Ledger</span></div>
    <button type="button" class="workspace-rail-add" aria-label="记一笔" @click="($event.currentTarget as HTMLElement).focus({ preventScroll: true }); emit('quickAdd')"><Plus :size="22" aria-hidden="true" /><span v-if="expanded">记一笔</span></button>
    <nav aria-label="主导航" data-projection="rail" class="workspace-rail-nav">
      <button
        v-for="item in items" :key="item.id" type="button" class="workspace-destination"
        :title="item.label" :aria-label="item.label" :aria-current="activeId === item.id ? 'page' : undefined"
        @click="emit('navigate', item.id)"
      >
        <component :is="navigationIcons[item.id]" :size="21" aria-hidden="true" />
        <span :class="expanded ? '' : 'workspace-rail-tooltip'">{{ item.label }}</span>
      </button>
      <button type="button" class="workspace-destination" title="更多" aria-label="打开更多导航" :aria-expanded="menuOpen" aria-controls="workspace-functions" @click="emit('more', $event)">
        <Ellipsis :size="22" aria-hidden="true" /><span :class="expanded ? '' : 'workspace-rail-tooltip'">更多</span>
      </button>
    </nav>
    <div class="workspace-rail-tools">
      <button type="button" class="workspace-icon-button" aria-label="我的" title="设置" :aria-current="activeId === 'settings' ? 'page' : undefined" @click="emit('navigate', 'settings')"><User :size="20" aria-hidden="true" /></button>
      <button type="button" class="workspace-icon-button" :aria-label="dark ? '切换到浅色模式' : '切换到深色模式'" :title="dark ? '浅色模式' : '深色模式'" @click="emit('theme')"><component :is="dark ? Sun : Moon" :size="20" aria-hidden="true" /></button>
      <button type="button" class="workspace-icon-button workspace-mode-toggle" :disabled="!canCustomize" aria-label="切换到顶部导航" title="切换到顶部导航" @click="emit('mode')"><PanelTop :size="20" aria-hidden="true" /></button>
      <button type="button" class="workspace-icon-button" :aria-label="expanded ? '收起侧边栏' : '展开侧边栏'" :title="expanded ? '收起侧边栏' : '展开侧边栏'" :aria-expanded="expanded" @click="expanded = !expanded"><component :is="expanded ? PanelLeftClose : PanelLeftOpen" :size="20" aria-hidden="true" /></button>
    </div>
  </aside>
</template>
