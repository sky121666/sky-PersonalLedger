<script setup lang="ts">
import { computed, nextTick, ref, watch, onMounted, onBeforeUnmount } from 'vue'
import { GripHorizontal, Minus } from '@lucide/vue'
import { packWidgets, type ColumnCount } from './layout'
import { getWidgetDefinition, type WidgetInstance, type HomeLayout, type ViewportKind, type WidgetSize } from './model'
import WidgetMenu from './WidgetMenu.vue'
import { useWidgetDrag } from '@/composables/useWidgetDrag'
const props = defineProps<{ layout: HomeLayout; viewport: ViewportKind; columns: ColumnCount; editing: boolean; contentRevision?: unknown; accountNames?: Record<string, string> }>()
const emit = defineEmits<{ move: [id: string, offset: number]; resize: [id: string, size: WidgetSize]; remove: [id: string]; configure: [id: string] }>()
const element = ref<HTMLElement | null>(null)
const gridWidth = ref(0)
const order = computed(() => props.layout.orders[props.viewport])
const placements = computed(() => packWidgets(props.layout.widgets, order.value, props.columns, props.viewport))
function labelFor(widget: WidgetInstance) { return widget.kind === 'account' ? `指定账户 · ${props.accountNames?.[widget.config.accountId] ?? widget.config.accountId}` : getWidgetDefinition(widget.kind).title }
async function removeWidget(id: string) {
  const index = order.value.indexOf(id)
  const neighbor = order.value[index + 1] ?? order.value[index - 1]
  emit('remove', id)
  await nextTick()
  const cell = Array.from(element.value?.querySelectorAll<HTMLElement>('[data-widget-id]') ?? [])
    .find(item => item.dataset.widgetId === neighbor)
  const target = cell?.querySelector<HTMLElement>('.widget-menu-trigger')
    ?? document.querySelector<HTMLElement>('.widget-editor-toolbar .widget-toolbar-icon:not(:disabled)')
  target?.focus({ preventScroll: true })
  target?.scrollIntoView({ block: 'nearest', behavior: 'instant' })
}
const ordered = computed(() => order.value.map(id => ({ widget: props.layout.widgets.find(w => w.id === id)!, placement: placements.value.find(p => p.id === id)! })))
let pointer: number | null = null; let autoFrame: number | null = null; let x = 0; let y = 0
let scroller: HTMLElement | null = null
let ghost: HTMLElement | null = null
let dragOrigin = { x: 0, y: 0 }
let movementAnimations: Animation[] = []
let mounted = false
let motionGeneration = 0
const drag = useWidgetDrag({ getOrder: () => order.value, getPlacements: () => Array.from(element.value?.querySelectorAll<HTMLElement>('[data-widget-id]') ?? []).map(el => ({ id: el.dataset.widgetId!, ...rect(el) })), move: (id, offset) => emit('move', id, offset), cancel: () => {}, getScrollOffset: () => scroller?.scrollTop ?? 0 })
function rect(el: HTMLElement) { const r = el.getBoundingClientRect(); return { left: r.left, top: r.top, width: r.width, height: r.height } }
function cleanup(resumeMotion = true) {
  if (autoFrame !== null) cancelAnimationFrame(autoFrame)
  autoFrame = null
  window.removeEventListener('keydown', key, true); window.removeEventListener('blur', cancel)
  if (pointer !== null && element.value?.hasPointerCapture(pointer)) element.value.releasePointerCapture(pointer)
  pointer = null
  ghost?.remove(); ghost = null
  if (resumeMotion) movementAnimations.forEach(animation => { if (animation.playState === 'paused') animation.play() })
}
function updateOffset() {
  if (ghost) ghost.style.transform = `translate(${x - dragOrigin.x}px, ${y - dragOrigin.y}px) scale(1.015)`
}
function stopMotion() {
  movementAnimations.forEach(animation => animation.cancel())
  movementAnimations = []
}
function createGhost(id: string) {
  const cell = Array.from(element.value?.querySelectorAll<HTMLElement>('[data-widget-id]') ?? []).find(item => item.dataset.widgetId === id)
  const renderer = cell?.querySelector<HTMLElement>('.widget-renderer')
  if (!renderer) return
  const bounds = renderer.getBoundingClientRect()
  ghost = document.createElement('div')
  ghost.className = 'widget-drag-preview'
  ghost.inert = true
  ghost.setAttribute('aria-hidden', 'true')
  Object.assign(ghost.style, { left: `${bounds.left}px`, top: `${bounds.top}px`, width: `${bounds.width}px`, height: `${bounds.height}px` })
  // A DOM snapshot avoids mounting a second data-reading Vue widget.
  const snapshot = renderer.cloneNode(true) as HTMLElement
  snapshot.querySelectorAll('[id]').forEach(node => node.removeAttribute('id'))
  ghost.appendChild(snapshot)
  document.body.appendChild(ghost)
  const originals = renderer.querySelectorAll<HTMLElement>('*')
  snapshot.querySelectorAll<HTMLElement>('*').forEach((node, index) => {
    node.scrollTop = originals[index]?.scrollTop ?? 0
    node.scrollLeft = originals[index]?.scrollLeft ?? 0
  })
}
function cancel() { drag.cancel(); cleanup() }
function key(event: KeyboardEvent) { if (event.key === 'Escape' && drag.active.value) { event.preventDefault(); event.stopImmediatePropagation(); cancel() } }
function tick() {
  if (!drag.active.value) return
  if (scroller) {
    const bounds = scroller.getBoundingClientRect()
    if (x < Math.max(0, bounds.left) || x > Math.min(window.innerWidth, bounds.right) || y < Math.max(0, bounds.top) || y > Math.min(window.innerHeight, bounds.bottom)) { autoFrame = requestAnimationFrame(tick); return }
    if (y < bounds.top + 48) scroller.scrollTop -= 8
    else if (y > bounds.bottom - 48) scroller.scrollTop += 8
  }
  updateOffset(); drag.update(x, y); autoFrame = requestAnimationFrame(tick)
}
function start(event: PointerEvent, id: string) {
  if (!props.editing || !event.isPrimary || event.button !== 0) return
  drag.cancel(); cleanup(false)
  movementAnimations.forEach(animation => { if (animation.playState === 'running') animation.pause() })
  scroller = element.value?.closest<HTMLElement>('.workspace-content') ?? null
  x = event.clientX; y = event.clientY
  if (!drag.start(id, x, y)) return
  dragOrigin = { x, y }; createGhost(id); updateOffset()
  event.preventDefault(); (event.currentTarget as HTMLElement).focus({ preventScroll: true })
  pointer = event.pointerId; element.value?.setPointerCapture(pointer)
  window.addEventListener('keydown', key, true); window.addEventListener('blur', cancel)
  autoFrame = requestAnimationFrame(tick)
}
function move(event: PointerEvent) { if (pointer === event.pointerId) { x = event.clientX; y = event.clientY; updateOffset(); drag.update(x, y) } }
function finish(event: PointerEvent) { if (pointer !== event.pointerId) return; drag.finish(event.clientX, event.clientY); cleanup() }
let observer: ResizeObserver | null = null
let widthFrame: number | null = null
let nextWidth = 0
onMounted(() => {
  mounted = true
  gridWidth.value = element.value?.clientWidth ?? 0
  if (typeof ResizeObserver !== 'undefined' && element.value) {
    observer = new ResizeObserver(entries => {
      const width = entries[0]?.contentRect.width ?? 0
      if (width === nextWidth) return
      nextWidth = width
      if (widthFrame !== null) return
      widthFrame = requestAnimationFrame(() => {
        widthFrame = null
        if (nextWidth !== gridWidth.value) { gridWidth.value = nextWidth; if (drag.active.value) cancel() }
      })
    })
    observer.observe(element.value)
  }
})
watch(() => [props.editing, props.viewport, props.columns, props.contentRevision, JSON.stringify(props.layout)], cancel)
watch(() => [props.editing, props.viewport, props.columns], stopMotion)
watch(() => JSON.stringify(props.layout), async () => {
  const generation = ++motionGeneration
  const cells = Array.from(element.value?.querySelectorAll<HTMLElement>('[data-widget-id]') ?? [])
  const previous = new Map(cells.map(cell => [cell.dataset.widgetId, cell.getBoundingClientRect()]))
  stopMotion()
  if (!mounted || !props.editing || window.matchMedia('(prefers-reduced-motion: reduce)').matches) return
  await nextTick()
  if (!mounted || generation !== motionGeneration || !props.editing) return
  for (const cell of element.value?.querySelectorAll<HTMLElement>('[data-widget-id]') ?? []) {
    if (!cell.animate) continue
    const before = previous.get(cell.dataset.widgetId)
    const after = cell.getBoundingClientRect()
    const from = before ? { transform: `translate(${before.left - after.left}px, ${before.top - after.top}px)` } : { opacity: 0, transform: 'scale(.98)' }
    if (!before || before.left !== after.left || before.top !== after.top) {
      movementAnimations.push(cell.animate([from, { opacity: 1, transform: 'none' }], { duration: 260, easing: 'cubic-bezier(.22,1,.36,1)' }))
    }
  }
})
onBeforeUnmount(() => { mounted = false; motionGeneration++; stopMotion(); observer?.disconnect(); if (widthFrame !== null) cancelAnimationFrame(widthFrame); cancel() })
defineExpose({ element, cancelDrag: cancel })
</script>
<template>
  <section ref="element" class="widget-grid" :class="{ 'widget-grid-editing': editing }" aria-label="首页小组件" :style="{ gridTemplateColumns: `repeat(${columns}, minmax(0, 1fr))` }" @pointermove="move" @pointerup="finish" @pointercancel="cancel" @lostpointercapture="cancel">
    <div v-for="({ widget, placement }, index) in ordered" :key="widget.id" class="widget-cell widget-edit-cell" :data-widget-id="widget.id" :data-widget-size="widget.sizes[viewport]" :class="{ 'widget-drag-source': drag.active.value?.id === widget.id, 'widget-drag-target': drag.active.value?.target === widget.id }" :style="{ gridRow: `${placement.row + 1} / span ${placement.rowSpan}`, gridColumn: `${placement.column + 1} / span ${placement.columnSpan}` }">
      <template v-if="editing">
        <button type="button" class="widget-remove-button" :aria-label="`移除${labelFor(widget)}（两端）`" title="从桌面与手机首页移除，可撤销" @click="removeWidget(widget.id)"><Minus :size="16" aria-hidden="true" /></button>
        <button type="button" class="widget-drag-handle" :aria-label="`拖动${labelFor(widget)}`" title="拖动排序；也可打开选项移动" @pointerdown="start($event, widget.id)" @keydown.up.prevent="emit('move', widget.id, -1)" @keydown.down.prevent="emit('move', widget.id, 1)"><GripHorizontal :size="20" aria-hidden="true" /></button>
        <WidgetMenu :label="labelFor(widget)" :widget="widget" :viewport="viewport" :first="index === 0" :last="index === ordered.length - 1" @move="emit('move', widget.id, $event)" @resize="emit('resize', widget.id, $event)" @remove="removeWidget(widget.id)" @configure="emit('configure', widget.id)" />
      </template>
      <div class="widget-renderer" :inert="editing || undefined"><slot :widget="widget" /></div>
    </div>
  </section>
  <p class="sr-only" role="status" aria-live="polite">{{ drag.active.value ? '正在拖动，按 Escape 取消' : '' }}</p>
</template>
<style scoped>
.widget-edit-cell{position:relative;display:flex;flex-direction:column;min-width:0;min-height:0}.widget-renderer{flex:1;display:flex;min-width:0;min-height:0}.widget-renderer>*{width:100%;flex:1}
.widget-grid-editing .widget-edit-cell{border-radius:24px;outline:1px solid #007aff55;outline-offset:2px}
.widget-drag-handle,.widget-remove-button{position:absolute;top:-16px;z-index:3;display:grid;place-items:center;width:44px;height:44px;border:0;border-radius:50%;color:#54545c;background:transparent}
.widget-drag-handle{left:calc(50% - 22px);touch-action:none;cursor:grab}
.widget-remove-button{left:-8px;cursor:pointer}
.widget-drag-handle::before,.widget-remove-button::before{content:"";position:absolute;inset:8px;border-radius:50%;background:#f6f6f9;box-shadow:0 1px 6px #0002;z-index:-1}
.widget-drag-source{outline:2px dashed #007aff}.widget-drag-source .widget-renderer{opacity:.3}.widget-drag-source .widget-drag-handle{cursor:grabbing}
.widget-drag-target:not(.widget-drag-source){outline:3px solid #007aff;outline-offset:3px}
.widget-drag-handle:focus-visible,.widget-remove-button:focus-visible{outline:3px solid #007aff}
.dark .widget-drag-handle,.dark .widget-remove-button{color:#f5f5f7}
.dark .widget-drag-handle::before,.dark .widget-remove-button::before{background:#3a3a3e}
@media(max-width:767px){.widget-remove-button{display:none}}
@media(prefers-reduced-motion:no-preference){.widget-drag-handle,.widget-remove-button{animation:widget-controls-in 160ms ease-out}@keyframes widget-controls-in{from{opacity:0;transform:scale(.8)}to{opacity:1;transform:scale(1)}}}
</style>
