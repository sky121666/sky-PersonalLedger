<script setup lang="ts">
import { computed, nextTick, onMounted, onBeforeUnmount, ref } from 'vue'
import { Ellipsis, ArrowUp, ArrowDown, Settings2, Minus } from '@lucide/vue'
import { getWidgetDefinition, type WidgetInstance, type ViewportKind, type WidgetSize } from './model'
const props = defineProps<{ widget: WidgetInstance; viewport: ViewportKind; first: boolean; last: boolean; label: string }>()
const emit = defineEmits<{ move: [offset: number]; resize: [size: WidgetSize]; remove: []; configure: [] }>()
const labels = { small: '小', medium: '中', large: '大' }
const sizes = computed(() => getWidgetDefinition(props.widget.kind).supportedSizes)
const trigger = ref<HTMLButtonElement | null>(null)
const panel = ref<HTMLElement | null>(null)
const open = ref(false)
const position = ref<{ left: string; top: string; maxHeight?: string }>({ left: '0px', top: '0px' })
const panelId = computed(() => `widget-options-${props.widget.id}`)

function close(restoreFocus = false) {
  if (!open.value) return
  open.value = false
  if (restoreFocus) trigger.value?.focus({ preventScroll: true })
}
async function toggle() {
  if (open.value) return close()
  open.value = true
  await nextTick()
  place()
  await nextTick()
  if (open.value) panel.value?.querySelector<HTMLElement>('select, button:not(:disabled)')?.focus({ preventScroll: true })
}
function place() {
  if (!open.value || !trigger.value || !panel.value) return
  const anchor = trigger.value.getBoundingClientRect()
  const scroller = trigger.value.closest('.workspace-content')?.getBoundingClientRect()
  const toolbar = document.querySelector('.widget-editor-toolbar')?.getBoundingClientRect()
  const mobileNav = document.querySelector('.workspace-mobile-nav')?.getBoundingClientRect()
  const top = Math.max(0, scroller?.top ?? 0, toolbar?.bottom ?? 0)
  const bottom = Math.min(window.innerHeight, scroller?.bottom ?? window.innerHeight, mobileNav?.top ?? window.innerHeight)
  if (anchor.bottom <= top || anchor.top >= bottom) return close(true)
  const bounds = panel.value.getBoundingClientRect()
  position.value = {
    left: `${Math.max(12, Math.min(anchor.right - bounds.width, window.innerWidth - bounds.width - 12))}px`,
    top: `${Math.max(top + 8, Math.min(anchor.bottom + 6, bottom - bounds.height - 8))}px`,
    maxHeight: `${Math.max(44, bottom - top - 16)}px`,
  }
}
function outside(event: Event) {
  if (event.target instanceof Node && !trigger.value?.contains(event.target) && !panel.value?.contains(event.target)) close()
}
function escape(event: KeyboardEvent) {
  if (open.value && event.key === 'Escape') { event.preventDefault(); event.stopPropagation(); close(true) }
}
function move(offset: number) { close(true); emit('move', offset) }
function configure() { close(true); emit('configure') }
function remove() { close(true); emit('remove') }
function onScroll(event: Event) {
  if (!(event.target instanceof Node) || !panel.value?.contains(event.target)) place()
}
function hideLeavingPanel(element: Element) {
  element.setAttribute('aria-hidden', 'true')
  element.setAttribute('inert', '')
  element.removeAttribute('id')
}
onMounted(() => {
  document.addEventListener('pointerdown', outside, true)
  document.addEventListener('focusin', outside)
  document.addEventListener('keydown', escape, true)
  window.addEventListener('resize', onScroll)
  window.addEventListener('scroll', onScroll, true)
})
onBeforeUnmount(() => {
  document.removeEventListener('pointerdown', outside, true)
  document.removeEventListener('focusin', outside)
  document.removeEventListener('keydown', escape, true)
  window.removeEventListener('resize', onScroll)
  window.removeEventListener('scroll', onScroll, true)
})
</script>
<template>
  <button ref="trigger" type="button" class="widget-menu-trigger" :aria-label="`${label}选项`" :aria-expanded="open" :aria-controls="panelId" @click="toggle"><Ellipsis :size="18" aria-hidden="true" /></button>
  <Teleport to="body">
    <Transition name="widget-options" @before-leave="hideLeavingPanel">
    <section v-if="open" :id="panelId" ref="panel" class="widget-options-panel" :style="position" role="region" :aria-label="`${label}选项菜单`">
      <strong>{{ label }}</strong>
      <label v-if="sizes.length > 1" class="widget-options-size">尺寸
        <select :aria-label="`${label}尺寸`" :value="widget.sizes[viewport]" @change="emit('resize', ($event.target as HTMLSelectElement).value as WidgetSize)">
          <option v-for="size in sizes" :key="size" :value="size">{{ labels[size] }}</option>
        </select>
      </label>
      <button type="button" :aria-label="`${label}：上移`" :disabled="first" @click="move(-1)"><ArrowUp :size="16" aria-hidden="true" />向前移动</button>
      <button type="button" :aria-label="`${label}：下移`" :disabled="last" @click="move(1)"><ArrowDown :size="16" aria-hidden="true" />向后移动</button>
      <button v-if="widget.kind === 'account'" type="button" :aria-label="`配置${label}`" @click="configure"><Settings2 :size="16" aria-hidden="true" />更换账户</button>
      <button type="button" class="widget-options-remove" :aria-label="`移除${label}（两端）`" @click="remove"><Minus :size="16" aria-hidden="true" />从两端移除</button>
    </section>
    </Transition>
  </Teleport>
</template>
<style scoped>
.widget-menu-trigger{position:absolute;right:-8px;top:-16px;z-index:4;display:grid;place-items:center;width:44px;height:44px;border:0;border-radius:50%;background:transparent;cursor:pointer;color:#54545c;scroll-margin-block:88px 100px}
.widget-menu-trigger::before{content:"";position:absolute;inset:8px;border-radius:50%;background:#f6f6f9;box-shadow:0 1px 6px #0002;z-index:-1}
.widget-menu-trigger:hover::before{background:#e5e5ea}
.widget-options-panel{position:fixed;z-index:60;width:min(236px,calc(100vw - 24px));max-height:calc(100dvh - 24px);overflow:auto;padding:8px;border:1px solid #7d7d8726;border-radius:18px;background:#fafafaf5;color:#1d1d1f;backdrop-filter:blur(24px);box-shadow:0 12px 44px #0003;font-size:13px}
.widget-options-panel>strong{display:block;padding:6px 10px;font-size:12px;color:#63636b;overflow-wrap:anywhere}
.widget-options-panel button,.widget-options-size{display:flex;align-items:center;gap:10px;min-height:44px;padding:6px 10px;width:100%;border-radius:10px;text-align:left}
.widget-options-panel button:hover{background:#007aff12}.widget-options-panel button:disabled{opacity:.35;cursor:default}
.widget-options-size{justify-content:space-between;border-bottom:1px solid #7d7d8726;border-radius:0;margin-bottom:4px}.widget-options-size select{min-width:88px;min-height:44px;padding:0 10px;border-radius:10px;background:#76768012;color:inherit}
.widget-options-panel :focus-visible,.widget-menu-trigger:focus-visible{outline:3px solid #007aff;outline-offset:2px}
.dark .widget-options-panel{background:#28282bf5;color:#f5f5f7;border-color:#ffffff1a}
.dark .widget-options-panel>strong{color:#a1a1aa}
.dark .widget-menu-trigger{color:#f5f5f7}
.dark .widget-menu-trigger::before{background:#3a3a3e}
.widget-options-panel .widget-options-remove{display:none}
@media(max-width:767px){.widget-options-panel .widget-options-remove{display:flex;color:#dc2626}.dark .widget-options-panel .widget-options-remove{color:#f87171}}
.widget-options-enter-active{transition:opacity 140ms ease,transform 140ms cubic-bezier(.22,1,.36,1)}.widget-options-leave-active{transition:opacity 100ms ease;pointer-events:none}.widget-options-enter-from{opacity:0;transform:translateY(-4px) scale(.98)}.widget-options-leave-to{opacity:0}
@media(prefers-reduced-motion:reduce){.widget-options-enter-active,.widget-options-leave-active{transition:none}}
</style>
