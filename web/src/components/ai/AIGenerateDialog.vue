<script setup lang="ts">
import { computed, reactive, ref, watch } from 'vue'
import { ChevronDown, Sparkles } from '@lucide/vue'
import AppDialog from '@/components/ui/AppDialog.vue'
import type { AIProvider, GenerateAIReportParams } from '@/api/ai'
import { aiReportPeriod, type AIReportPeriodPreset } from '@/utils/aiReportPeriod'

const props = defineProps<{ providers: AIProvider[]; initial?: GenerateAIReportParams | null; uncertain?: boolean; returnFocus?: HTMLElement | null; fallbackFocus?: HTMLElement | null }>()
const emit = defineEmits<{ close: []; generate: [params: GenerateAIReportParams] }>()
const enabled = computed(() => props.providers.filter(provider => provider.enabled))
const preset = ref<AIReportPeriodPreset>(props.initial ? 'custom' : 'month_to_date')
const form = reactive<GenerateAIReportParams>({ report_type: 'monthly', ...aiReportPeriod('month_to_date'), provider_id: enabled.value[0]?.id || '', mask_names: true, ...props.initial })
const error = ref('')
const service = computed(() => enabled.value.find(provider => provider.id === form.provider_id))
const acknowledged = ref(false)
function applyPeriod() { if (preset.value !== 'custom') Object.assign(form, aiReportPeriod(preset.value)) }
watch(() => form.report_type, type => {
  if (preset.value === 'custom') return
  if (type === 'weekly') preset.value = 'week_to_date'
  else if (type === 'monthly') preset.value = 'month_to_date'
  applyPeriod()
})
function submit() {
  error.value = ''
  if (!form.period_start || !form.period_end || form.period_start > form.period_end) { error.value = '开始日期不能晚于结束日期。'; return }
  if (!service.value) { error.value = '请选择一个已启用的 AI 服务。'; return }
  if (props.uncertain && !acknowledged.value) { error.value = '请先确认你了解上次请求的结果仍未确认。'; return }
  emit('generate', { ...form })
}
</script>

<template>
  <AppDialog title="新建分析" mobile-fullscreen :return-focus="returnFocus" :fallback-focus="fallbackFocus" @close="emit('close')">
    <form id="ai-generate-form" class="ai-generate-form" @submit.prevent="submit">
      <div v-if="uncertain" class="ai-inline-warning"><p>上次请求的结果仍未确认。再次提交可能产生额外模型费用，请优先刷新报告状态。</p><label class="ai-check"><input v-model="acknowledged" type="checkbox" />我已检查状态，仍要重新生成</label></div>
      <label class="finance-field">报告类型<select v-model="form.report_type" class="finance-input"><optgroup label="定期总结"><option value="weekly">每周总结</option><option value="monthly">月度总结</option></optgroup><optgroup label="专项分析"><option value="family">家庭分析</option><option value="budget">预算建议</option></optgroup></select></label>
      <label class="finance-field">时间范围<select v-model="preset" class="finance-input" @change="applyPeriod"><option value="week_to_date">本周至今</option><option value="previous_week">上周</option><option value="month_to_date">本月至今</option><option value="previous_month">上月</option><option value="custom">自定义</option></select></label>
      <div v-if="preset === 'custom'" class="finance-form-grid ai-date-grid"><label class="finance-field">开始日期<input v-model="form.period_start" required type="date" class="finance-input" /></label><label class="finance-field">结束日期<input v-model="form.period_end" required type="date" class="finance-input" /></label></div>
      <p v-else class="ai-period-summary" data-testid="ai-period-summary">{{ form.period_start }} 至 {{ form.period_end }}</p>
      <details class="ai-disclosure" :open="!service"><summary>使用的服务 <span>{{ service?.name || '请选择服务' }} <ChevronDown :size="15" /></span></summary><label class="finance-field">AI 服务<select v-model="form.provider_id" required class="finance-input"><option disabled value="">请选择服务</option><option v-for="provider in enabled" :key="provider.id" :value="provider.id">{{ provider.name }} · {{ provider.model }}</option></select></label><p v-if="!service" class="finance-form-error">原服务已停用或删除，请选择其他服务。</p><p v-else class="ai-caption">{{ service.model }}</p></details>
      <div class="ai-privacy">
        <label class="ai-check"><input v-model="form.mask_names" type="checkbox" /><span><strong>替换成员和账户名称</strong><small>使用成员1、账户1等名称；分类名称仍会发送。</small></span></label>
        <details class="ai-disclosure"><summary>将发送哪些数据？<ChevronDown :size="15" /></summary><p>所选周期的收支汇总、主要支出分类、成员支出、账户净变化及预算汇总。不发送交易备注和附件。</p><p>预算按所选结束日期对应的月份统计，可能与收支周期不同。财务汇总会发送给所选 AI 服务，可能产生模型费用。</p></details>
      </div>
      <p v-if="error" role="alert" class="finance-form-error">{{ error }}</p>
    </form>
    <template #footer><button type="button" class="finance-button is-subtle" @click="emit('close')">取消</button><button type="submit" form="ai-generate-form" class="finance-button is-primary" :disabled="!enabled.length"><Sparkles :size="17" />开始分析</button></template>
  </AppDialog>
</template>
