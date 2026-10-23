<script setup lang="ts">
import { nextTick, onBeforeUnmount, ref, useId, watch, type Component } from 'vue'
import { MoreHorizontal } from '@lucide/vue'
const props = defineProps<{ label: string; actions: { id: string; label: string; icon?: Component; danger?: boolean }[] }>()
const emit = defineEmits<{ action: [id: string] }>()
const trigger = ref<HTMLButtonElement | null>(null)
const panel = ref<HTMLElement | null>(null)
const open = ref(false)
const id = useId()
const placement = ref({ left: '0px', top: '0px' })
const upward = ref(false)

function close(restore = false) {
  open.value = false
  if (restore) trigger.value?.focus({ preventScroll: true })
}
function position() {
  if (!trigger.value || !panel.value) return
  const bounds = trigger.value.getBoundingClientRect()
  const nav = document.querySelector<HTMLElement>('.workspace-mobile-nav')
  const navTop = nav?.getClientRects().length ? nav.getBoundingClientRect().top - 8 : innerHeight - 12
  const bottom = Math.min(navTop, innerHeight - 12)
  if (bounds.bottom < 0 || bounds.top > bottom) { close(); return }
  upward.value = bounds.bottom + 6 + panel.value.offsetHeight > bottom
  placement.value = {
    left: `${Math.max(8, Math.min(innerWidth - panel.value.offsetWidth - 8, bounds.right - panel.value.offsetWidth))}px`,
    top: `${Math.max(8, upward.value ? bounds.top - panel.value.offsetHeight - 6 : bounds.bottom + 6)}px`,
  }
}
async function toggle() {
  if (open.value) return close(true)
  open.value = true
  await nextTick()
  position()
  panel.value?.querySelector<HTMLButtonElement>('button')?.focus({ preventScroll: true })
}
function outside(event: MouseEvent) {
  if (event.target instanceof Node && !panel.value?.contains(event.target) && !trigger.value?.contains(event.target)) close()
}
function keyboard(event: KeyboardEvent) {
  if (event.key === 'Escape' || event.key === 'Tab') {
    if (event.key === 'Escape') { event.preventDefault(); event.stopPropagation() }
    close(true)
    return
  }
  if (!['ArrowDown', 'ArrowUp', 'Home', 'End'].includes(event.key)) return
  event.preventDefault()
  const buttons = [...(panel.value?.querySelectorAll<HTMLButtonElement>('button') ?? [])]
  const index = buttons.indexOf(document.activeElement as HTMLButtonElement)
  const next = event.key === 'Home' ? 0 : event.key === 'End' ? buttons.length - 1 :
    (index + (event.key === 'ArrowDown' ? 1 : -1) + buttons.length) % buttons.length
  buttons[next]?.focus()
}
function listeners(add: boolean) {
  if (add) {
    document.addEventListener('click', outside)
    window.addEventListener('resize', position)
    window.addEventListener('scroll', position, true)
  } else {
    document.removeEventListener('click', outside)
    window.removeEventListener('resize', position)
    window.removeEventListener('scroll', position, true)
  }
}
watch(open, listeners)
onBeforeUnmount(() => listeners(false))
</script>

<template>
  <button ref="trigger" type="button" class="finance-icon-button" :aria-label="label" aria-haspopup="menu" :aria-expanded="open"
    :aria-controls="open ? id : undefined" @click="toggle"><MoreHorizontal :size="19" /></button>
  <Teleport to="body">
    <Transition name="finance-menu">
      <div v-if="open" :id="id" ref="panel" role="menu" :aria-label="label" class="finance-popover"
        :class="{ 'opens-up': upward }" :style="placement" @keydown="keyboard" @click.stop>
        <button v-for="action in props.actions" :key="action.id" type="button" role="menuitem" :class="{ 'is-danger': action.danger }"
          @click="close(true); emit('action', action.id)"><component :is="action.icon" v-if="action.icon" :size="16" aria-hidden="true" />{{ action.label }}</button>
      </div>
    </Transition>
  </Teleport>
</template>
