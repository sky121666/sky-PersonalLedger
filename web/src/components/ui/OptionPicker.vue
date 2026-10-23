<script setup lang="ts">
import { computed, nextTick, onBeforeUnmount, ref, useId, watch } from 'vue'
import { Check, ChevronDown, CreditCard } from '@lucide/vue'
const props = defineProps<{ modelValue: string; options: { value: string; label: string; detail?: string }[]; label: string; disabled?: boolean }>()
const emit = defineEmits<{ 'update:modelValue': [value: string] }>()
const root = ref<HTMLElement | null>(null)
const trigger = ref<HTMLButtonElement | null>(null)
const panel = ref<HTMLElement | null>(null)
const open = ref(false)
const id = useId()
const selected = computed(() => props.options.find(option => option.value === props.modelValue))
function close(restore = false) { open.value = false; if (restore) trigger.value?.focus({ preventScroll: true }) }
async function toggle() {
  if (props.disabled) return
  if (open.value) return close(true)
  open.value = true
  await nextTick()
  ;(panel.value?.querySelector<HTMLElement>('[aria-selected="true"]') ?? panel.value?.querySelector<HTMLElement>('[role="option"]'))?.focus({ preventScroll: true })
}
function outside(event: MouseEvent) { if (event.target instanceof Node && !root.value?.contains(event.target)) close() }
function keyboard(event: KeyboardEvent, index: number) {
  if (event.key === 'Escape' || event.key === 'Tab') {
    if (event.key === 'Escape') { event.preventDefault(); event.stopPropagation() }
    close(true)
    return
  }
  if (!['ArrowDown','ArrowUp','Home','End'].includes(event.key)) return
  event.preventDefault()
  const next = event.key === 'Home' ? 0 : event.key === 'End' ? props.options.length - 1 :
    (index + (event.key === 'ArrowDown' ? 1 : -1) + props.options.length) % props.options.length
  const option = panel.value?.querySelectorAll<HTMLElement>('[role="option"]')[next]
  option?.focus({ preventScroll: true })
  option?.scrollIntoView({ block: 'nearest' })
}
watch(open, value => { if (value) document.addEventListener('click', outside); else document.removeEventListener('click', outside) })
watch(() => props.disabled, value => { if (value) close() })
onBeforeUnmount(() => document.removeEventListener('click', outside))
</script>

<template>
  <div ref="root" class="finance-option-picker">
    <button ref="trigger" class="finance-button finance-option-trigger" type="button" :aria-label="label" :disabled="disabled" aria-haspopup="listbox"
      :data-value="modelValue" :aria-expanded="open" :aria-controls="open ? id : undefined" @click="toggle" @keydown.down.prevent="!open && toggle()">
      <CreditCard :size="17" aria-hidden="true" /><span>{{ selected?.label || '请选择' }}</span><ChevronDown :size="16" aria-hidden="true" />
    </button>
    <Transition name="finance-menu">
      <div v-if="open" :id="id" ref="panel" role="listbox" :aria-label="label" class="finance-option-panel">
        <button v-for="(option,index) in options" :key="option.value" type="button" role="option" :value="option.value"
          :aria-selected="modelValue === option.value" @keydown="keyboard($event,index)" @click="emit('update:modelValue',option.value); close(true)">
          <span><strong>{{ option.label }}</strong><small v-if="option.detail">{{ option.detail }}</small></span><Check v-if="modelValue === option.value" :size="16" aria-hidden="true" />
        </button>
      </div>
    </Transition>
  </div>
</template>

<style scoped>
.finance-option-picker { position: relative; min-width: 0; }
.finance-option-trigger { max-width: 100%; background: transparent; text-align: left; padding: 0 4px; gap: 9px; }
.finance-option-trigger > span { flex: 1; min-width: 0; max-width: 360px; overflow-wrap: anywhere; }
.finance-option-trigger > svg { flex: none; color: var(--fp-secondary); }
.finance-option-trigger > svg:last-child { margin-left: 18px; transition: transform 160ms ease; }
.finance-option-trigger[aria-expanded="true"] > svg:last-child { transform: rotate(180deg); }
.finance-option-panel { position: absolute; left: 0; top: calc(100% + 6px); z-index: 40; width: min(360px,calc(100vw - 40px)); max-height: min(320px,45dvh); overflow-y: auto; padding: 6px; border: 1px solid var(--fp-line); border-radius: 16px; background: var(--fp-solid); box-shadow: 0 14px 36px #16284424; transform-origin: top left; scrollbar-width: thin; }
.finance-option-panel button { display: flex; align-items: center; gap: 10px; justify-content: space-between; min-height: 54px; width: 100%; padding: 9px; border-radius: 11px; text-align: left; }
.finance-option-panel button[aria-selected="true"] { background: var(--fp-blue-soft); }
.finance-option-panel strong { display: block; font-size: 13px; font-weight: 550; overflow-wrap: anywhere; }
.finance-option-panel small { display: block; margin-top: 5px; font-size: 12px; color: var(--fp-secondary); }
.finance-option-panel svg { flex: none; color: var(--fp-blue); }
</style>
