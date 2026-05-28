import { get, post, put, del } from '@/utils/request'

export interface AIProvider {
  id: string
  name: string
  provider_type: string
  base_url: string
  model: string
  enabled: boolean
  created_at: string
  updated_at: string
}

export interface AIProviderPreset {
  id: string
  name: string
  provider_type: string
  base_url: string
  model: string
  models: string[]
}

export interface SaveAIProviderParams {
  name: string
  provider_type?: string
  base_url: string
  api_key?: string
  model: string
  enabled: boolean
}

export interface AIReport {
  id: string
  report_type: string
  period_start: string
  period_end: string
  status: string
  snapshot_json: string
  content_json: string
  provider_id: string
  provider_name: string
  model: string
  prompt_version: string
  error_message?: string
  created_at: string
  updated_at: string
}

export interface GenerateAIReportParams {
  report_type: string
  provider_id?: string
  period_start: string
  period_end: string
}

export const aiApi = {
  listProviderPresets(): Promise<AIProviderPreset[]> {
    return get<AIProviderPreset[]>('/ai/providers/presets')
  },

  listProviders(): Promise<AIProvider[]> {
    return get<AIProvider[]>('/ai/providers')
  },

  createProvider(params: SaveAIProviderParams): Promise<AIProvider> {
    return post<AIProvider>('/ai/providers', params)
  },

  updateProvider(id: string, params: SaveAIProviderParams): Promise<AIProvider> {
    return put<AIProvider>(`/ai/providers/${id}`, params)
  },

  deleteProvider(id: string): Promise<void> {
    return del<void>(`/ai/providers/${id}`)
  },

  testProvider(id: string): Promise<{ ok: boolean }> {
    return post<{ ok: boolean }>(`/ai/providers/${id}/test`)
  },

  listReports(): Promise<AIReport[]> {
    return get<AIReport[]>('/ai/reports')
  },

  getReport(id: string): Promise<AIReport> {
    return get<AIReport>(`/ai/reports/${id}`)
  },

  generateReport(params: GenerateAIReportParams): Promise<AIReport> {
    return post<AIReport>('/ai/reports/generate', params)
  },

  deleteReport(id: string): Promise<void> {
    return del<void>(`/ai/reports/${id}`)
  }
}
