<script setup lang="ts">
import { computed } from 'vue'
import { useRouter } from 'vue-router'
import { ArrowLeft, Check, CreditCard, PanelLeft, Palette } from '@lucide/vue'
import FinancePage from '@/components/ui/FinancePage.vue'
import SelectionControl from '@/components/ui/SelectionControl.vue'
import { useThemeStore, type ThemePreference } from '@/stores/theme'
import { useWorkspacePreferencesStore } from '@/stores/workspacePreferences'
import { toast } from '@/composables/useToast'

const router = useRouter()
const theme = useThemeStore()
const preferences = useWorkspacePreferencesStore()
const canCustomize = computed(() => preferences.ready && !preferences.navigationIssue)
const themes: { value: ThemePreference; label: string }[] = [
  { value: 'light', label: '浅色' }, { value: 'dark', label: '深色' }, { value: 'system', label: '跟随系统' },
]
function selectTheme(value: ThemePreference) {
  if (!theme.setPreference(value)) toast.error('外观偏好未保存，请检查浏览器存储后重试')
}
function selectNavigation(value: string) {
  if (!canCustomize.value || (value !== 'rail' && value !== 'top')) return
  try { preferences.setNavigationMode(value) } catch { toast.error('导航偏好未保存，请重新加载后重试') }
}
</script>

<template>
  <FinancePage title="外观设置">
    <template #actions><button class="finance-button appearance-back" aria-label="返回设置" @click="router.push('/settings')"><ArrowLeft :size="17" /><span>返回</span></button></template>
    <section class="finance-card finance-card-padding">
      <h2 class="text-sm font-semibold">界面主题</h2>
      <div class="appearance-theme-options">
        <button v-for="option in themes" :key="option.value" type="button" class="appearance-theme-option"
          :data-theme="option.value" :aria-label="option.label" :aria-pressed="theme.preference === option.value" @click="selectTheme(option.value)">
          <span class="appearance-theme-thumb" aria-hidden="true"><i class="mini-sidebar"></i><i class="mini-heading"></i><i class="mini-panel"></i><i class="mini-lines"></i></span>
          <span v-if="theme.preference === option.value" class="appearance-check" aria-hidden="true"><Check :size="13" /></span>
          <span class="appearance-theme-label">{{ option.label }}</span>
        </button>
      </div>
      <div class="appearance-setting">
        <span class="appearance-setting-label"><PanelLeft :size="18" />桌面导航</span>
        <SelectionControl :model-value="preferences.navigation.mode" :disabled="!canCustomize" label="桌面导航方式"
          :options="[{ value: 'rail', label: '侧栏' }, { value: 'top', label: '顶部' }]" @update:model-value="selectNavigation" />
      </div>
      <p v-if="!canCustomize" role="status" class="finance-muted mt-2">导航偏好尚不可用，请使用页面顶部的偏好重试入口。手机始终使用底部导航。</p>
      <div class="appearance-setting"><span class="appearance-setting-label"><Palette :size="18" />主色</span><span class="appearance-blue">#007AFF</span></div>
    </section>
    <section class="finance-card finance-card-padding">
      <div class="finance-card-heading"><h2>页面预览</h2><span class="finance-muted">外观示意</span></div>
      <div class="appearance-page-preview">
        <div class="appearance-preview-heading"><CreditCard :size="19" /><strong>账户与分期</strong></div>
        <div class="appearance-preview-values"><div><span>待还本金</span><strong>¥ —</strong></div><div><span>已入账利息</span><strong>¥ —</strong></div><div><span>累计分配</span><strong class="appearance-blue">¥ —</strong></div></div>
        <div class="appearance-preview-bottom"><span>分期计划</span><span class="appearance-preview-pill">还款中</span></div>
      </div>
    </section>
  </FinancePage>
</template>

<style scoped>
.appearance-theme-options { display: grid; grid-template-columns: repeat(3,minmax(0,1fr)); gap: 14px; margin: 22px 0 20px; }
.appearance-theme-option { min-width: 0; position: relative; border: 1px solid var(--fp-line); border-radius: 16px; padding: 5px; text-align: left; }
.appearance-theme-option[aria-pressed="true"] { outline: 2px solid var(--fp-blue); outline-offset: 2px; }
.appearance-theme-thumb { display: block; position: relative; height: 116px; overflow: hidden; border-radius: 11px; background: #eceef3; }
.appearance-theme-thumb i { position: absolute; display: block; border-radius: 5px; }
.mini-sidebar { left: 8%; top: 12%; bottom: 12%; width: 16%; background: #fff; }
.mini-heading { top: 14%; left: 30%; width: 48%; height: 5%; background: #b9bbc2; }
.mini-panel { left: 30%; right: 8%; top: 29%; height: 39%; background: white; box-shadow: 0 2px 8px #00000008; }
.mini-panel::after { content: ""; position: absolute; left: 15%; top: 33%; width: 45%; height: 8px; border-radius: 3px; background: #007aff; opacity: .65; }
.mini-lines { top: 76%; left: 30%; width: 54%; height: 6%; background: #daddE4; }
[data-theme="dark"] .appearance-theme-thumb { background: #141417; }
[data-theme="dark"] .mini-panel,[data-theme="dark"] .mini-sidebar { background: #29292d; }
[data-theme="dark"] .mini-lines { background: #3a3a3f; }
[data-theme="system"] .appearance-theme-thumb { background: linear-gradient(90deg,#eceef3 50%,#141417 50%); }
[data-theme="system"] .mini-panel { background: linear-gradient(90deg,#fff 32%,#29292d 32%); }
.appearance-theme-label { display: flex; min-height: 36px; align-items: center; padding: 2px 7px; font-size: 13px; }
.appearance-check { position: absolute; display: grid; place-items: center; top: 11px; right: 11px; width: 19px; height: 19px; border-radius: 50%; background: #007aff; color: white; }
.appearance-setting { display: flex; align-items: center; justify-content: space-between; gap: 12px; padding: 18px 0; border-top: 1px solid var(--fp-line); }
.appearance-setting-label { display: flex; align-items: center; gap: 10px; font-size: 14px; font-weight: 500; }
.appearance-setting-label svg { color: var(--fp-secondary); }
.appearance-blue { color: var(--fp-blue); }
.appearance-page-preview { border: 1px solid var(--fp-line); border-radius: 18px; overflow: hidden; }
.appearance-preview-heading { display: flex; align-items: center; gap: 8px; padding: 18px; font-size: 13px; }
.appearance-preview-heading svg { color: var(--fp-blue); }
.appearance-preview-values { display: grid; grid-template-columns: repeat(3,minmax(0,1fr)); padding: 6px 18px 20px; gap: 12px; }
.appearance-preview-values span { display: block; font-size: 12px; color: var(--fp-secondary); }
.appearance-preview-values strong { display: block; margin-top: 8px; font-size: 22px; font-weight: 600; }
.appearance-preview-bottom { display: flex; align-items: center; justify-content: space-between; padding: 16px 18px; background: var(--fp-blue-soft); font-size: 13px; }
.appearance-preview-pill { border-radius: 9px; color: var(--fp-blue); font-size: 12px; }
@media (max-width:767px) {
  .appearance-theme-options { gap: 9px; }
  .appearance-theme-thumb { height: 78px; }
  .appearance-theme-label { padding: 2px 4px; font-size: 12px; }
  .appearance-setting-label { font-size: 13px; }
  .appearance-setting { gap: 8px; }
  .appearance-preview-values span { font-size: 11px; }
}
</style>
