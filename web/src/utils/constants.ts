export const CATEGORY_EMOJIS = [
  '🍽️', '🥤', '🍔', '🍜', '🍱', // 餐饮
  '🚗', '🚌', '🚇', '🚕', '✈️', // 交通
  '🛍️', '👕', '👠', '👜', '💄', // 购物
  '🏠', '💡', '💧', '🌐', '🧹', // 居住
  '🎮', '🎬', '🎤', '🎳', '🎲', // 娱乐
  '💊', '🏥', '🦷', '👓', '🚑', // 医疗
  '📚', '🖊️', '🎓', '🎨', '🎹', // 教育
  '💰', '💸', '🏦', '📈', '💎', // 金融
  '🎁', '🧧', '💐', '🎂', '📱', // 社交/其他
  '👔', '🏃', '🐶', '🐱', '💼', // 其他
  '👶', '👵', '🔧', '🔨', '📄'  // 其他
]

export const CATEGORY_COLORS = [
  '#EF4444', // Red
  '#F97316', // Orange
  '#F59E0B', // Amber
  '#84CC16', // Lime
  '#10B981', // Emerald
  '#06B6D4', // Cyan
  '#3B82F6', // Blue
  '#6366F1', // Indigo
  '#8B5CF6', // Violet
  '#EC4899', // Pink
  '#64748B', // Slate
  '#71717A', // Zinc
]

// 支出分类
export const EXPENSE_CATEGORIES = [
  { name: '餐饮', icon: '🍽️', color: '#EF4444' },
  { name: '交通', icon: '🚗', color: '#F97316' },
  { name: '购物', icon: '🛍️', color: '#EC4899' },
  { name: '娱乐', icon: '🎮', color: '#8B5CF6' },
  { name: '居住', icon: '🏠', color: '#06B6D4' },
  { name: '医疗', icon: '💊', color: '#10B981' },
  { name: '教育', icon: '📚', color: '#3B82F6' },
  { name: '通讯', icon: '📱', color: '#6366F1' },
  { name: '服饰', icon: '👔', color: '#F59E0B' },
  { name: '美容', icon: '💄', color: '#EC4899' },
  { name: '运动', icon: '🏃', color: '#84CC16' },
  { name: '旅行', icon: '✈️', color: '#06B6D4' },
  { name: '社交', icon: '👥', color: '#F97316' },
  { name: '宠物', icon: '🐱', color: '#F59E0B' },
  { name: '数码', icon: '💻', color: '#3B82F6' },
  { name: '家居', icon: '🛋️', color: '#84CC16' },
  { name: '汽车', icon: '🚙', color: '#64748B' },
  { name: '礼物', icon: '🎁', color: '#EC4899' },
  { name: '办公', icon: '📎', color: '#71717A' },
  { name: '零食', icon: '🍿', color: '#F97316' },
  { name: '水果', icon: '🍎', color: '#EF4444' },
  { name: '饮品', icon: '🥤', color: '#06B6D4' },
  { name: '早餐', icon: '🥐', color: '#F59E0B' },
  { name: '午餐', icon: '🍱', color: '#EF4444' },
  { name: '晚餐', icon: '🍜', color: '#EF4444' },
  { name: '外卖', icon: '🥡', color: '#F97316' },
  { name: '快递', icon: '📦', color: '#71717A' },
  { name: '话费', icon: '📞', color: '#3B82F6' },
  { name: '水电', icon: '💡', color: '#F59E0B' },
  { name: '房租', icon: '🏢', color: '#6366F1' },
  { name: '保险', icon: '🛡️', color: '#10B981' },
  { name: '其他', icon: '💳', color: '#64748B' }
]

// 收入分类
export const INCOME_CATEGORIES = [
  { name: '工资', icon: '💰', color: '#10B981' },
  { name: '奖金', icon: '🎁', color: '#F59E0B' },
  { name: '理财', icon: '📈', color: '#3B82F6' },
  { name: '兼职', icon: '💼', color: '#6366F1' },
  { name: '报销', icon: '📄', color: '#06B6D4' },
  { name: '红包', icon: '🧧', color: '#EF4444' },
  { name: '退款', icon: '💸', color: '#84CC16' },
  { name: '利息', icon: '🏦', color: '#3B82F6' },
  { name: '股息', icon: '💹', color: '#10B981' },
  { name: '租金', icon: '🏠', color: '#F97316' },
  { name: '中奖', icon: '🎰', color: '#EC4899' },
  { name: '补贴', icon: '🎫', color: '#8B5CF6' },
  { name: '稿费', icon: '✍️', color: '#06B6D4' },
  { name: '其他', icon: '💵', color: '#64748B' }
]

export const DEFAULT_CATEGORY_MAP: Record<string, string> = {
  // 支出
  '餐饮': '🍽️', '交通': '🚗', '购物': '🛍️', '娱乐': '🎮',
  '居住': '🏠', '医疗': '💊', '教育': '📚', '通讯': '📱',
  '服饰': '👔', '美容': '💄', '运动': '🏃', '旅行': '✈️',
  '社交': '👥', '宠物': '🐱', '数码': '💻', '家居': '🛋️',
  '汽车': '🚙', '礼物': '🎁', '办公': '📎', '零食': '🍿',
  '水果': '🍎', '饮品': '🥤', '早餐': '🥐', '午餐': '🍱',
  '晚餐': '🍜', '外卖': '🥡', '快递': '📦', '话费': '📞',
  '水电': '💡', '房租': '🏢', '保险': '🛡️',
  // 收入
  '工资': '💰', '奖金': '🎁', '理财': '📈', '兼职': '💼',
  '报销': '📄', '红包': '🧧', '退款': '💸', '利息': '🏦',
  '股息': '💹', '租金': '🏠', '中奖': '🎰', '补贴': '🎫',
  '稿费': '✍️',
  // 其他
  '其他': '💳'
}

export function getCategoryEmoji(name: string, icon?: string): string {
  if (icon) return icon
  return DEFAULT_CATEGORY_MAP[name] || '💳'
}

export const ACCOUNT_TYPES: Record<string, string> = {
  'cash': '现金',
  'bank_card': '银行卡',
  'alipay': '支付宝',
  'wechat': '微信',
  'savings': '储蓄',
  'investment': '投资',
  'fund': '基金',
  'stock': '股票',
  'crypto': '加密货币',
  'prepaid': '预付卡',
  'qq_pay': 'QQ钱包',
  'jd_pay': '京东',
  'apple_pay': 'Apple',
  'credit': '信用卡',
  'loan': '贷款',
  'mortgage': '房贷',
  'car_loan': '车贷',
  'consumer_loan': '消费贷',
  'huabei': '花呗',
  'baitiao': '白条',
  'other': '其他'
}

export const ACCOUNT_ICONS: Record<string, string> = {
  'cash': '💵',
  'bank_card': '💳',
  'alipay': '🔵',
  'wechat': '🟢',
  'savings': '💰',
  'investment': '📈',
  'fund': '📊',
  'stock': '📉',
  'crypto': '🪙',
  'prepaid': '🎫',
  'qq_pay': '🐧',
  'jd_pay': '🐶',
  'apple_pay': '🍎',
  'credit': '💳',
  'loan': '💸',
  'mortgage': '🏠',
  'car_loan': '🚗',
  'consumer_loan': '💳',
  'huabei': '🌼',
  'baitiao': '📝',
  'other': '📦'
}

export const TRANSACTION_TYPES: Record<string, string> = {
  'income': '收入',
  'expense': '支出',
  'transfer': '转账'
}

// 中国用户习惯：红涨绿跌 (收入红，支出绿)
export const TYPE_COLORS: Record<string, string> = {
  'income': 'text-red-500',
  'expense': 'text-green-500',
  'transfer': 'text-blue-500'
}

export const BG_COLORS: Record<string, string> = {
  'income': 'bg-red-50 dark:bg-red-900/20',
  'expense': 'bg-green-50 dark:bg-green-900/20',
  'transfer': 'bg-blue-50 dark:bg-blue-900/20'
}

export const AMOUNT_COLORS: Record<string, string> = {
  'income': 'text-emerald-500',
  'expense': 'text-red-500',
  'transfer': 'text-gray-500 dark:text-gray-400',
  'positive': 'text-emerald-500', // 资产正增长/结余
  'negative': 'text-red-500', // 资产负增长/亏损
  'debt': 'text-gray-900 dark:text-gray-100' // 负债
}

export function getAccountTypeName(type: string): string {
  return ACCOUNT_TYPES[type] || '未知账户'
}

export function getAccountIcon(type: string): string {
  return ACCOUNT_ICONS[type] || '💳'
}
