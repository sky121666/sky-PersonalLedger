<script setup lang="ts">
import { nextTick, onBeforeUnmount, onMounted, ref, watch } from 'vue'
import type { Component } from 'vue'
const props = defineProps<{
  modelValue: string
  options: readonly { value: string; label: string; icon?: Component }[]
  label: string
  disabled?: boolean
  solid?: boolean
}>()
const emit = defineEmits<{ 'update:modelValue': [value: string] }>()
const root = ref<HTMLElement | null>(null)
const marker = ref<HTMLElement | null>(null)
let animation: Animation | undefined
let observer: ResizeObserver | undefined
let reducedMotion: MediaQueryList | undefined
function motionChanged() { if (reducedMotion?.matches) animation?.finish() }

function position(animate = false) {
  if (!root.value || !marker.value) return
  const selected = root.value.querySelector<HTMLElement>('[aria-pressed="true"]')
  if (!selected || !selected.getClientRects().length) return
  const previous = marker.value.getBoundingClientRect()
  const bounds = root.value.getBoundingClientRect()
  const target = selected.getBoundingClientRect()
  const transform = `translate(${target.left - bounds.left - root.value.clientLeft}px, ${target.top - bounds.top - root.value.clientTop}px)`
  animation?.cancel()
  marker.value.style.width = `${target.width}px`
  marker.value.style.height = `${target.height}px`
  marker.value.style.transform = transform
  if (animate && previous.width && !matchMedia('(prefers-reduced-motion: reduce)').matches) {
    animation = marker.value.animate([
      { transform: `translate(${previous.left - bounds.left - root.value.clientLeft}px, ${target.top - bounds.top - root.value.clientTop}px) scaleX(${previous.width / target.width})` },
      { transform },
    ], { duration: 210, easing: 'cubic-bezier(.23,1,.32,1)' })
  }
}
function keyboard(event: KeyboardEvent, index: number) {
  if (!['ArrowLeft', 'ArrowRight', 'Home', 'End'].includes(event.key) || props.disabled) return
  event.preventDefault()
  const next = event.key === 'Home' ? 0 : event.key === 'End' ? props.options.length - 1 :
    (index + (event.key === 'ArrowRight' ? 1 : -1) + props.options.length) % props.options.length
  const option = props.options[next]
  if (!option) return
  emit('update:modelValue', option.value)
  root.value?.querySelectorAll<HTMLButtonElement>('button')[next]?.focus({ preventScroll: true })
}
watch(() => props.modelValue, () => nextTick(() => position(true)))
onMounted(() => {
  reducedMotion = matchMedia('(prefers-reduced-motion: reduce)')
  reducedMotion.addEventListener('change', motionChanged)
  position()
  observer = new ResizeObserver(() => position())
  if (root.value) observer.observe(root.value)
})
onBeforeUnmount(() => { observer?.disconnect(); animation?.cancel(); reducedMotion?.removeEventListener('change', motionChanged) })
</script>

<template>
  <div ref="root" class="finance-selection" :class="{ 'is-solid': solid }" role="group" :aria-label="label">
    <span ref="marker" class="finance-selection-marker" aria-hidden="true"></span>
    <button v-for="(option, index) in options" :key="option.value" type="button" :disabled="disabled"
      :aria-pressed="modelValue === option.value" @click="emit('update:modelValue', option.value)" @keydown="keyboard($event, index)">
      <component :is="option.icon" v-if="option.icon" :size="17" aria-hidden="true" />{{ option.label }}
    </button>
  </div>
</template>
