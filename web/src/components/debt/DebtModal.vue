<script setup lang="ts">
import AppDialog from '@/components/ui/AppDialog.vue'
defineProps<{ title: string; busy?: boolean; returnFocus?: HTMLElement | null; fallbackFocus?: HTMLElement | null }>()
const emit = defineEmits<{ close: [] }>()
</script>

<template>
  <AppDialog :title="title" :busy="busy" :return-focus="returnFocus" :fallback-focus="fallbackFocus" @close="emit('close')">
    <slot /><template v-if="$slots.footer" #footer><slot name="footer" /></template>
  </AppDialog>
</template>
