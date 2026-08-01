export type AccountType =
  | 'cash' | 'bank_card' | 'alipay' | 'wechat' | 'savings' | 'investment'
  | 'fund' | 'stock' | 'crypto' | 'prepaid' | 'qq_pay' | 'jd_pay' | 'apple_pay'
  | 'credit' | 'loan' | 'mortgage' | 'car_loan' | 'consumer_loan'
  | 'huabei' | 'baitiao' | 'receivable' | 'payable' | 'other'

export const DEBT_ACCOUNT_TYPES: readonly AccountType[] = [
  'credit', 'loan', 'mortgage', 'car_loan', 'consumer_loan', 'huabei', 'baitiao', 'payable',
]

export function isDebtAccount(type: string): boolean {
  return DEBT_ACCOUNT_TYPES.includes(type as AccountType)
}
