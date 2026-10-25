import { get, post } from '@/utils/request'
import type { AccountLog } from '@/api/accountLog'
import type { Transaction } from '@/api/transaction'

export interface DebtCapabilities {
  contract_version: number
  multiple_plans: boolean
  explicit_allocation: boolean
  reversal: boolean
  managed_accounts: string
  external_cash_interest: boolean
  operation_history?: boolean
}

export interface DebtPlan {
  id: string
  account_id: string | null
  name: string
  original_principal: number
  opening_principal: number
  principal_balance: number
  interest_balance: number
  estimated_interest: number | null
  principal_paid: number
  interest_paid: number
  status: 'active' | 'cleared' | 'cancelled'
  version: number
  created_at: string
}

export interface DebtOperation {
  id: string
  kind: string
  account_id: string | null
  standalone_plan_id: string | null
  source_account_id: string | null
  source_kind: string
  amount: number
  unapplied_amount: number
  unplanned_payment: number
  payment_id: string | null
  reversal_of: string | null
  reversed_by: string | null
  occurred_at: string
  created_at: string
}

export interface DebtAllocation {
  id: string
  plan_id: string
  operation_id: string
  principal_delta: number
  interest_delta: number
  principal_paid_delta: number
  interest_paid_delta: number
  cash_interest: number
}

export interface DebtOperationDetails {
  operation: DebtOperation
  allocations: DebtAllocation[] | null
  account_effects: AccountLog[] | null
  transactions: Transaction[] | null
  // Optional to detect a backend from before the Web read-model extension.
  unallocated_amount?: number
  active_allocations?: DebtOperation[]
}

export interface DebtPaymentPart {
  plan_id: string
  principal: number
  booked_interest: number
  cash_interest: number
}

export interface DebtPlanPayload {
  name: string
  scope: 'account' | 'standalone'
  account_id?: string
  original_principal: number
  opening_principal: number
  booked_interest: number
  estimated_interest?: number
}

export interface DebtPaymentPayload {
  account_id?: string
  standalone_plan_id?: string
  source_kind: 'account' | 'external'
  source_account_id?: string
  amount: number
  allocations: DebtPaymentPart[]
  unplanned_amount: number
  unapplied_amount: number
  occurred_at?: string
}

export interface DebtAllocationPayload {
  allocations: DebtPaymentPart[]
  unplanned_amount: number
  replace_operation_id?: string
}

export interface DebtOperationQuery {
  plan_id?: string
  standalone_only?: boolean
  before?: string
}

export type DebtCommand =
  | { kind: 'plan'; target: string; payload: DebtPlanPayload }
  | { kind: 'payment'; target: string; payload: DebtPaymentPayload }
  | { kind: 'allocation'; target: string; payload: DebtAllocationPayload }
  | { kind: 'interest'; target: string; payload: { amount: number; occurred_at?: string } }
  | { kind: 'reversal'; target: string; payload: Record<string, never> }

const id = encodeURIComponent

export const debtApi = {
  capabilities: () => get<DebtCapabilities>('/debt/capabilities'),
  plans: () => get<DebtPlan[]>('/debt/plans'),
  operations: (accountId = '', query: DebtOperationQuery = {}) => get<DebtOperation[]>('/debt/operations', {
    params: { ...(accountId ? { account_id: accountId } : {}), ...query },
  }),
  details: (operationId: string) => get<DebtOperationDetails>(`/debt/operations/${id(operationId)}`),
  send(command: DebtCommand, key: string): Promise<DebtOperation | DebtPlan> {
    const body = { ...command.payload, idempotency_key: key }
    switch (command.kind) {
      case 'plan': return post<DebtPlan>('/debt/plans', body)
      case 'payment': return post<DebtOperation>('/debt/payments', body)
      case 'allocation': return post<DebtOperation>(`/debt/operations/${id(command.target)}/allocations`, body)
      case 'interest': return post<DebtOperation>(`/debt/plans/${id(command.target)}/interest`, body)
      case 'reversal': return post<DebtOperation>(`/debt/operations/${id(command.target)}/reverse`, body)
    }
  },
}
