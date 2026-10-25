<script setup lang="ts">
import { ChevronRight } from '@lucide/vue'
import '@/assets/home-cards.css'
defineProps<{
  title: string
  size: 'small' | 'medium' | 'large'
  tone?: 'default' | 'blue' | 'green' | 'amber' | 'violet' | 'cyan' | 'assets'
  interactive?: boolean
}>()
const emit = defineEmits<{ (e: 'activate'): void }>()
</script>

<template>
  <article
    class="home-widget"
    :class="[`home-widget-${size}`, tone && `home-widget-${tone}`, { 'home-widget-interactive': interactive }]"
    :data-interactive="interactive || undefined"
    :aria-label="title"
  >
    <header class="home-widget-header">
      <h3><slot name="icon" />{{ title }}</h3>
      <button v-if="interactive" type="button" class="widget-link" aria-label="查看详情" @click.stop="emit('activate')">
        <slot name="badge"><ChevronRight :size="16" aria-hidden="true" /></slot>
      </button>
      <slot v-else name="badge" />
    </header>
    <div class="home-widget-body" :aria-label="`${title}内容`"><slot /></div>
    <footer v-if="$slots.footer" class="home-widget-footer">
      <slot name="footer" />
    </footer>
  </article>
</template>
