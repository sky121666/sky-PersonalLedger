<script setup lang="ts">
import type { Component } from 'vue'
import { ArrowLeft } from '@lucide/vue'
defineProps<{ title: string; context?: string; subtitle?: string; icon?: Component; tone?: 'blue' | 'orange' | 'cyan' | 'green' | 'purple'; backLabel?: string; wide?: boolean }>()
defineEmits<{ back: [] }>()
</script>

<template>
  <section class="finance-page">
    <div class="finance-frame" :class="{ 'is-wide': wide }">
      <header class="finance-page-head">
        <div class="finance-heading">
          <button v-if="backLabel" type="button" class="finance-icon-button finance-back" :aria-label="backLabel" @click="$emit('back')"><ArrowLeft :size="19" /></button>
          <slot name="heading">
            <span v-if="icon" class="finance-page-badge" :data-tone="tone || 'blue'" aria-hidden="true"><component :is="icon" :size="23" :stroke-width="1.7" /></span>
            <div class="min-w-0">
              <div class="finance-title-line"><h1>{{ title }}</h1><span v-if="context" class="finance-context">{{ context }}</span></div>
              <p v-if="subtitle" class="finance-subtitle">{{ subtitle }}</p>
            </div>
          </slot>
        </div>
        <div v-if="$slots.actions" class="finance-head-actions"><slot name="actions" /></div>
      </header>
      <div class="finance-content"><slot /></div>
    </div>
  </section>
</template>
