<script setup lang="ts">
import { computed } from 'vue'
import {
  Banknote, Landmark, CreditCard, CircleDot, MessageCircle, MessageSquare,
  ShoppingBag, Smartphone, Flower2, Scroll, Building2, TrendingUp,
  PieChart, BarChart2, Bitcoin, Ticket, ClipboardList, FileText, Wallet,
  Home, Car, Repeat, Receipt, Calendar, Star, Tag
} from 'lucide-vue-next'

const props = defineProps<{
  icon: string
  size?: number
  class?: string
}>()

// Icon name to component map
const iconMap: Record<string, any> = {
  'banknote': Banknote,
  'banknot': Banknote,
  'landmark': Landmark,
  'credit-card': CreditCard,
  'credit_card': CreditCard,
  'circle-dot': CircleDot,
  'message-circle': MessageCircle,
  'message-square': MessageSquare,
  'shopping-bag': ShoppingBag,
  'smartphone': Smartphone,
  'flower-2': Flower2,
  'scroll': Scroll,
  'building-2': Building2,
  'home': Home,
  'house': Home,
  'car': Car,
  'trending-up': TrendingUp,
  'pie-chart': PieChart,
  'bar-chart-2': BarChart2,
  'bitcoin': Bitcoin,
  'ticket': Ticket,
  'clipboard-list': ClipboardList,
  'file-text': FileText,
  'wallet': Wallet,
  'repeat': Repeat,
  'receipt': Receipt,
  'calendar': Calendar,
  'star': Star,
  'label': Tag
}

// Check if the icon is an emoji
const isEmoji = computed(() => {
  if (!props.icon) return false
  const emojiRegex = /^[\u{1F300}-\u{1F9FF}\u{2600}-\u{26FF}\u{2700}-\u{27BF}\u{1F600}-\u{1F64F}\u{1F680}-\u{1F6FF}\u{1F1E0}-\u{1F1FF}\u{2300}-\u{23FF}\u{2B50}\u{2B55}\u{3030}\u{303D}\u{3297}\u{3299}]/u
  return emojiRegex.test(props.icon)
})

// Get Lucide icon component by name
const lucideIcon = computed(() => {
  if (isEmoji.value || !props.icon) return null
  return iconMap[props.icon] || null
})

const iconSize = computed(() => props.size || 20)
</script>

<template>
  <span v-if="isEmoji" :class="props.class">{{ icon }}</span>
  <component 
    v-else-if="lucideIcon" 
    :is="lucideIcon" 
    :size="iconSize" 
    :class="props.class"
  />
  <span v-else :class="props.class">💳</span>
</template>
