import {
  Home, List, PieChart, ChartNoAxesCombined, Wallet, CreditCard, ArrowLeftRight,
  History, Users, Sparkles, ChartColumn, Shapes, Tags, Bookmark, Settings, Ellipsis,
} from '@lucide/vue'
import type { NavigationId } from './catalog'

export const navigationIcons = {
  home: Home, transactions: List, statistics: PieChart, budgets: ChartNoAxesCombined,
  accounts: Wallet, reminders: CreditCard, lendings: ArrowLeftRight, 'account-logs': History,
  family: Users, ai: Sparkles, report: ChartColumn, categories: Shapes, tags: Tags,
  templates: Bookmark, settings: Settings, more: Ellipsis,
} satisfies Record<NavigationId, unknown>
