<script setup lang="ts">
import { computed, onMounted, onBeforeUnmount, nextTick, ref, watch } from 'vue'
import { Search, X, Plus, Check, Wallet, ChartColumn, Bell, CalendarDays, Users, Sparkles, List, Target, CreditCard, ArrowLeftRight } from '@lucide/vue'
import { getWidgetDefinitions, type HomeLayout, type WidgetKind, type WidgetSize, type ViewportKind } from './model'
import HomeWidget from './HomeWidget.vue'
import { getWidgetUnit, packWidgets, type ColumnCount } from './layout'
import { createGalleryPreview } from './galleryPreview'
import type { Account } from '@/api/account'
import AccountPicker from './AccountPicker.vue'
const props = defineProps<{ layout: HomeLayout; viewport: ViewportKind; accounts: Account[]; accountsFailed: boolean; showAmounts?: boolean; initialAccountId?: string; initialSize?: WidgetSize; columns: ColumnCount; availableWidth: number }>()
const emit = defineEmits<{ close: []; add: [kind: WidgetKind, size: WidgetSize, accountId?: string] }>()
const dialog = ref<HTMLDialogElement | null>(null); const search = ref(''); const category = ref('all')
const list = ref<HTMLElement | null>(null)
const addButton = ref<HTMLButtonElement | null>(null)
const selected = ref<WidgetKind>(props.initialAccountId ? 'account' : 'budget'); const size = ref<WidgetSize>(props.initialSize ?? 'small'); const accountId = ref(props.initialAccountId ?? '')
const definitions = getWidgetDefinitions()
const categories = [{ id: 'all', title: '全部' }, { id: 'finance', title: '财务' }, { id: 'assets', title: '账户' }, { id: 'reminders', title: '提醒' }, { id: 'more', title: '更多' }]
const filtered = computed(() => definitions.filter(item => (category.value === 'all' || item.category === category.value) && item.title.includes(search.value.trim())))
const definition = computed(() => filtered.value.find(item => item.kind === selected.value))
const accountAvailable = computed(() => !props.accountsFailed && props.accounts.some(account => account.id === accountId.value && !account.is_archived))
const already = computed(() => props.layout.widgets.find(w => w.kind === selected.value && (w.kind !== 'account' || w.config.accountId === accountId.value)))
const icons = { netAssets: Wallet, monthlyFlow: ChartColumn, budget: Target, reminders: Bell, transactions: List, accounts: Wallet, account: CreditCard, calendar: CalendarDays, lending: ArrowLeftRight, family: Users, ai: Sparkles }
function isAdded(kind: WidgetKind) { return props.layout.widgets.some(widget => widget.kind === kind) }
const instance = computed(() => ({ id: 'gallery-preview', kind: selected.value, config: selected.value === 'account' ? { accountId: 'preview' } : {}, sizes: { desktop: size.value, mobile: size.value } }) as HomeLayout['widgets'][number])
const footprint = computed(() => {
  const placement = packWidgets([instance.value], [instance.value.id], props.columns, props.viewport)[0]!
  const cell = getWidgetUnit(props.availableWidth, props.columns)
  return { width: `${cell * placement.columnSpan + 16 * (placement.columnSpan - 1)}px` }
})
const preview = createGalleryPreview()
let scroller: HTMLElement | null = null; let oldOverflow = ''
const closing = ref(false)
let closeTimer: ReturnType<typeof setTimeout> | null = null
function choose(kind: WidgetKind) { selected.value = kind; size.value = props.initialAccountId && kind === 'account' ? props.initialSize ?? 'small' : definitions.find(d => d.kind === kind)!.supportedSizes[0] }
watch(filtered, items => {
  if (items.length && !items.some(item => item.kind === selected.value)) choose(items[0]!.kind)
})
function centerSelection() {
  if (!list.value || !window.matchMedia('(max-width: 767px)').matches) return
  const selectedButton = list.value.querySelector<HTMLElement>('[aria-pressed="true"]')
  if (!selectedButton) return
  const bounds = selectedButton.getBoundingClientRect()
  const container = list.value.getBoundingClientRect()
  list.value.scrollTo({ top: list.value.scrollTop + bounds.top - container.top - (container.height - bounds.height) / 2, behavior: 'auto' })
}
watch([selected, filtered], () => { void nextTick(centerSelection) })
function trapTab(event: KeyboardEvent) {
  if (event.defaultPrevented) return
  const nodes = Array.from(dialog.value?.querySelectorAll<HTMLElement>('button:not(:disabled),input:not(:disabled),select:not(:disabled),a[href],[tabindex="0"]') ?? []).filter(el => el.tabIndex >= 0 && !el.closest('[inert]') && el.getClientRects().length > 0)
  const first = nodes[0]; const last = nodes[nodes.length - 1]
  if (event.shiftKey && document.activeElement === first) { event.preventDefault(); last?.focus() }
  else if (!event.shiftKey && document.activeElement === last) { event.preventDefault(); first?.focus() }
}
function focusAfterAccount() {
  if (addButton.value && !addButton.value.disabled) addButton.value.focus()
  else dialog.value?.querySelector<HTMLButtonElement>('.gallery-close')?.focus()
}
function finishClose() { dialog.value?.close(); emit('close') }
function add() {
  if (closing.value || !definition.value || (definition.value.requiresAccount && !accountAvailable.value)) return
  emit('add', selected.value, size.value, accountId.value || undefined)
}
function close() {
  if (closing.value) return
  if (window.matchMedia('(prefers-reduced-motion: reduce)').matches) return finishClose()
  closing.value = true
  closeTimer = setTimeout(finishClose, 140)
}
onMounted(() => { scroller = document.querySelector('.workspace-content'); if (scroller) { oldOverflow = scroller.style.overflow; scroller.style.overflow = 'hidden' }; dialog.value?.showModal(); void nextTick(centerSelection) })
onBeforeUnmount(() => { if (closeTimer !== null) clearTimeout(closeTimer); dialog.value?.close(); if (scroller) scroller.style.overflow = oldOverflow })
</script>
<template>
  <dialog ref="dialog" class="widget-gallery" :class="{ 'is-closing': closing }" aria-label="组件画廊" @cancel.prevent="close" @keydown.tab="trapTab" @click="($event.target === dialog) && close()">
    <header><h2>小组件</h2><button type="button" class="gallery-close" aria-label="关闭组件画廊" @click="close"><X :size="20" aria-hidden="true" /></button></header>
    <div class="widget-gallery-body" :inert="closing || undefined">
      <aside>
        <label class="gallery-search"><Search :size="16" aria-hidden="true" /><input v-model="search" type="search" aria-label="搜索小组件" placeholder="搜索" /></label>
        <div class="gallery-categories" role="group" aria-label="组件分类"><button v-for="item in categories" :key="item.id" type="button" :aria-pressed="category === item.id" @click="category = item.id">{{ item.title }}</button></div>
        <div ref="list" class="widget-gallery-list"><button v-for="item in filtered" :key="item.kind" type="button" :aria-label="`预览${item.title}`" :aria-pressed="selected === item.kind" @click="choose(item.kind)"><component :is="icons[item.kind]" :size="17" aria-hidden="true" /><span>{{ item.title }}</span><small v-if="isAdded(item.kind)">已添加</small></button></div>
      </aside>
      <section aria-label="组件尺寸预览" class="widget-gallery-preview">
        <template v-if="definition">
          <div class="gallery-preview-heading"><h3>{{ definition.title }}</h3><p class="widget-muted">示例数据 · {{ viewport === 'desktop' ? '桌面' : '手机' }}</p></div>
          <div class="widget-preview-canvas" role="region" aria-label="真实尺寸预览画布" tabindex="0"><div class="widget-preview-surface" :style="footprint" inert><HomeWidget :instance="instance" :read-models="preview" :viewport="viewport" preview /></div></div>
          <div v-if="!(initialAccountId && selected === 'account')" class="widget-size-options" aria-label="预览尺寸"><button v-for="supported in definition.supportedSizes" :key="supported" type="button" :aria-label="({small:'小',medium:'中',large:'大'})[supported]" :aria-pressed="size === supported" @click="size = supported"><span class="gallery-size-shape" :class="`gallery-size-${supported}`" aria-hidden="true" />{{ ({small:'小',medium:'中',large:'大'})[supported] }}</button></div>
          <AccountPicker v-if="definition.requiresAccount" v-model="accountId" :accounts="accounts" :disabled="accountsFailed" :show-amounts="showAmounts" @tab-forward="focusAfterAccount" />
          <p v-if="definition.requiresAccount && accountsFailed" role="status">账户加载失败，请返回首页刷新后重试。</p>
          <button ref="addButton" type="button" class="widget-primary" :disabled="closing || (definition.requiresAccount && !accountAvailable)" @click="add"><component :is="already ? Check : Plus" :size="17" aria-hidden="true" />{{ already ? '定位已有组件' : initialAccountId && selected === 'account' ? '更新账户组件' : '添加到首页' }}</button>
        </template>
        <div v-else class="gallery-empty" role="status"><Search :size="28" aria-hidden="true" /><p>没有匹配的小组件</p></div>
      </section>
    </div>
  </dialog>
</template>
<style scoped>
.widget-gallery{margin:auto;width:min(1040px,calc(100vw - 24px));max-height:calc(100dvh - 32px);border:1px solid #dce2ed;border-radius:28px;padding:20px;background:#f7f8fcf5;color:#1d1d1f;box-shadow:0 28px 100px #10204033;overflow:auto;backdrop-filter:blur(24px)}
.dark .widget-gallery{background:#1c1c1e;color:#f5f5f7;border-color:#363639}
.widget-gallery::backdrop{background:#101c3244;backdrop-filter:blur(6px)}
header{display:flex;justify-content:space-between;align-items:center;margin-bottom:16px}h2,h3{font-weight:650}h2{font-size:19px}button,select,input{min-height:44px;border-radius:12px;padding:8px 12px;font:inherit}button{cursor:pointer}button:disabled{opacity:.4;cursor:default}button[aria-pressed=true]{background:#007aff1a;color:#007aff}button:focus-visible,input:focus-visible,select:focus-visible{outline:3px solid #007aff;outline-offset:2px}
.widget-gallery-body{display:grid;grid-template-columns:208px minmax(0,1fr);gap:24px}.widget-gallery-list{display:flex;flex-direction:column;gap:4px}.widget-gallery-list button{display:flex;align-items:center;gap:9px;text-align:left;font-size:13px}.widget-gallery-list span{flex:1}.widget-gallery-list small{font-size:10px;opacity:.7;white-space:nowrap}.widget-gallery-list svg{flex:none}
.gallery-search{display:flex;align-items:center;border-radius:12px;background:#76768014;padding-left:10px;margin-bottom:8px}.gallery-search input{width:100%;min-width:0;background:transparent;padding-left:7px}.gallery-close{display:grid;place-items:center;width:44px;padding:0;background:#76768014}
.gallery-categories{display:grid;grid-template-columns:repeat(3,minmax(0,1fr));gap:4px;margin-bottom:10px}.gallery-categories button{padding:6px 10px;border-radius:10px;font-size:12px;min-height:44px}
.widget-gallery-preview{align-self:start;display:flex;flex-direction:column;align-items:center;gap:16px;min-width:0;padding:16px;border-radius:20px;background:#76768009}.gallery-preview-heading{align-self:stretch;display:flex;flex-wrap:wrap;align-items:center;justify-content:space-between;gap:8px}
.widget-size-options{display:flex;gap:4px;background:#76768012;padding:3px;border-radius:16px}.widget-size-options button{display:flex;align-items:center;gap:8px}.gallery-size-shape{width:14px;height:14px;border:1.5px solid currentColor;border-radius:4px}.gallery-size-medium{width:25px}.gallery-size-large{width:22px;height:22px}
.widget-preview-canvas{width:100%;overflow:auto;min-width:0;padding:6px;display:flex;align-items:flex-start}.widget-preview-surface{flex:none;min-height:0;display:flex;margin:auto}.widget-preview-surface>*{width:100%}.widget-primary{display:flex;align-items:center;justify-content:center;gap:7px;background:#007aff;color:white;min-width:156px}.gallery-empty{min-height:320px;display:grid;place-content:center;justify-items:center;gap:12px;color:#8e8e93}
@media(max-width:767px){.widget-gallery-body{grid-template-columns:minmax(0,1fr);gap:16px}.widget-gallery-list{display:grid;grid-template-columns:repeat(2,minmax(0,1fr));max-height:184px;overflow-y:auto;overflow-x:hidden;overscroll-behavior:contain;padding:3px;gap:4px}.widget-gallery-list button{min-width:0;flex-wrap:wrap;gap:6px;font-size:12px;padding:8px}.widget-gallery-list small{font-size:9px}.widget-gallery{width:calc(100vw - 8px);max-width:calc(100vw - 8px);padding:10px;border-radius:24px}.widget-gallery-preview{padding:12px 0}.widget-preview-canvas{padding:0}.gallery-preview-heading{font-size:13px}aside select{margin-bottom:4px}}
@media(max-width:767px){.gallery-categories{display:flex;flex-wrap:wrap}}
@media(prefers-reduced-motion:no-preference){.widget-gallery[open]{animation:gallery-in 220ms cubic-bezier(.22,1,.36,1)}.widget-gallery.is-closing{animation:gallery-out 140ms ease-in forwards;pointer-events:none}@keyframes gallery-in{from{opacity:0;transform:translateY(18px) scale(.985)}to{opacity:1;transform:none}}@keyframes gallery-out{to{opacity:0;transform:translateY(8px) scale(.99)}}}
</style>
