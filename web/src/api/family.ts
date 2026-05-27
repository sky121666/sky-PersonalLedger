import { get, post, put, del } from '@/utils/request'

export interface FamilyMember {
  id: string
  name: string
  relationship: string
  avatar: string
  color: string
  sort_order: number
  is_default: boolean
  is_enabled: boolean
}

export interface SaveFamilyMemberParams {
  name: string
  relationship?: string
  avatar?: string
  color?: string
  sort_order?: number
  is_default?: boolean
  is_enabled?: boolean
}

export interface FamilyMemberSummary {
  member_id: string
  name: string
  relationship: string
  color: string
  expense_total: number
  count: number
}

export interface FamilySummary {
  month: string
  total_expense: number
  members: FamilyMemberSummary[]
}

export const familyApi = {
  listMembers(): Promise<FamilyMember[]> {
    return get<FamilyMember[]>('/family/members')
  },

  createMember(params: SaveFamilyMemberParams): Promise<FamilyMember> {
    return post<FamilyMember>('/family/members', params)
  },

  updateMember(id: string, params: SaveFamilyMemberParams): Promise<FamilyMember> {
    return put<FamilyMember>(`/family/members/${id}`, params)
  },

  deleteMember(id: string): Promise<void> {
    return del<void>(`/family/members/${id}`)
  },

  getSummary(month?: string): Promise<FamilySummary> {
    return get<FamilySummary>('/family/summary', {
      params: month ? { month } : undefined
    })
  }
}
