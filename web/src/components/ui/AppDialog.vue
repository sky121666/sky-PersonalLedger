<script lang="ts">
// Restore the original page state only after the last dialog closes, regardless of unmount order.
const openPanels: HTMLElement[] = []
let pageState: { app: HTMLElement | null; inert: boolean; overflow: string } | null = null
</script>

<script setup lang="ts">
import { nextTick, onBeforeUnmount, onMounted, ref, useId } from 'vue'
import { X } from '@lucide/vue'
const props = defineProps<{
  title: string
  closeLabel?: string
  initialFocus?: string
  busy?: boolean
  returnFocus?: HTMLElement | null
  fallbackFocus?: HTMLElement | null
  sheet?: boolean
  mobileFullscreen?: boolean
}>()
const emit = defineEmits<{ close: [] }>()
const dialog = ref<HTMLElement | null>(null)
const titleId = useId()
let previous: HTMLElement | null = null

function close() { if (!props.busy) emit('close') }
function keyboard(event: KeyboardEvent) {
  if (event.isComposing) return
  if (openPanels[openPanels.length - 1] !== dialog.value) return
  if (event.key === 'Escape') { event.preventDefault(); event.stopPropagation(); close(); return }
  if (event.key !== 'Tab' || !dialog.value) return
  const elements = [...dialog.value.querySelectorAll<HTMLElement>(
    'button:not(:disabled), input:not(:disabled), select:not(:disabled), textarea:not(:disabled), a[href], summary, [tabindex="0"]',
  )].filter(element => element.tabIndex >= 0 && !element.closest('[inert]') && element.getClientRects().length > 0)
  event.preventDefault()
  if (!elements.length) { dialog.value.focus(); return }
  // WebKit may skip buttons during native Tab traversal; keep the dialog order consistent.
  const current = elements.indexOf(document.activeElement as HTMLElement)
  const next = current < 0 ? (event.shiftKey ? elements.length - 1 : 0)
    : (current + (event.shiftKey ? -1 : 1) + elements.length) % elements.length
  elements[next]?.focus()
}
onMounted(async () => {
  previous = document.activeElement instanceof HTMLElement ? document.activeElement : null
  if (!dialog.value) return
  if (!openPanels.length) {
    const app = document.getElementById('app')
    pageState = { app, inert: app?.inert ?? false, overflow: document.body.style.overflow }
    if (app) app.inert = true
    document.body.style.overflow = 'hidden'
  }
  openPanels.push(dialog.value)
  document.addEventListener('keydown', keyboard, true)
  await nextTick()
  if (openPanels[openPanels.length - 1] !== dialog.value) return
  const initial = props.initialFocus ? dialog.value?.querySelector<HTMLElement>(props.initialFocus) : null
  const target = initial ?? dialog.value?.querySelector<HTMLElement>('h2')
  target?.focus({ preventScroll: true })
})
onBeforeUnmount(() => {
  document.removeEventListener('keydown', keyboard, true)
  const index = dialog.value ? openPanels.indexOf(dialog.value) : -1
  if (index !== -1) openPanels.splice(index, 1)
  if (!openPanels.length && pageState) {
    if (pageState.app) pageState.app.inert = pageState.inert
    document.body.style.overflow = pageState.overflow
    pageState = null
  }
  void nextTick(() => {
    const top = openPanels[openPanels.length - 1]
    const target = [props.returnFocus, props.fallbackFocus, previous].find(element =>
      element?.isConnected && (!top || top.contains(element)) && !element.matches(':disabled, [aria-disabled="true"]') && element.getClientRects().length > 0)
    const destination = target ?? top?.querySelector<HTMLElement>('h2')
    destination?.focus({ preventScroll: true })
  })
})
</script>

<template>
  <Teleport to="body">
    <Transition appear name="finance-dialog">
      <div class="finance-layer" :class="{ 'is-sheet': sheet, 'is-fullscreen-mobile': mobileFullscreen }" @click.self="close">
        <section ref="dialog" role="dialog" aria-modal="true" :aria-labelledby="titleId" tabindex="-1" :aria-busy="busy" class="finance-dialog-panel">
          <div v-if="sheet" class="finance-sheet-handle" aria-hidden="true"></div>
          <header class="finance-dialog-head">
            <h2 :id="titleId" tabindex="-1">{{ title }}</h2>
            <button type="button" :disabled="busy" :aria-label="closeLabel || `关闭${title}`" class="finance-icon-button" @click="close"><X :size="19" /></button>
          </header>
          <div class="finance-dialog-body"><slot /></div>
          <footer v-if="$slots.footer" class="finance-action-footer finance-dialog-footer"><slot name="footer" /></footer>
        </section>
      </div>
    </Transition>
  </Teleport>
</template>
