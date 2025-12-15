import { get, put, post } from '@/utils/request'

export interface NotificationSetting {
  id: number
  user_id: number
  enabled: boolean

  wecom_enabled: boolean
  wecom_webhook: string

  dingtalk_enabled: boolean
  dingtalk_webhook: string
  dingtalk_secret: string

  email_enabled: boolean
  smtp_host: string
  smtp_port: number
  smtp_user: string
  smtp_from: string
  email_to: string

  webhook_enabled: boolean
  webhook_url: string
  webhook_secret: string

  notify_payment_due: boolean
  notify_budget_alert: boolean
  notify_lending_due: boolean
  notify_login: boolean
  notify_annual_report: boolean
  advance_days: number
}

export interface UpdateNotificationParams {
  enabled: boolean

  wecom_enabled: boolean
  wecom_webhook: string

  dingtalk_enabled: boolean
  dingtalk_webhook: string
  dingtalk_secret: string

  email_enabled: boolean
  smtp_host: string
  smtp_port: number
  smtp_user: string
  smtp_password?: string
  smtp_from: string
  email_to: string

  webhook_enabled: boolean
  webhook_url: string
  webhook_secret: string

  notify_payment_due: boolean
  notify_budget_alert: boolean
  notify_lending_due: boolean
  notify_login: boolean
  notify_annual_report: boolean
  advance_days: number
}

export interface TestResult {
  success: boolean
  message: string
}

export const notificationApi = {
  getSettings(): Promise<NotificationSetting> {
    return get<NotificationSetting>('/notifications/settings')
  },

  updateSettings(params: UpdateNotificationParams): Promise<NotificationSetting> {
    return put<NotificationSetting>('/notifications/settings', params)
  },

  testWecom(webhook: string): Promise<TestResult> {
    return post<TestResult>('/notifications/test/wecom', { webhook })
  },

  testDingtalk(webhook: string, secret?: string): Promise<TestResult> {
    return post<TestResult>('/notifications/test/dingtalk', { webhook, secret })
  },

  testEmail(params: {
    smtp_host: string
    smtp_port: number
    smtp_user: string
    smtp_password?: string
    smtp_from?: string
  }): Promise<TestResult> {
    return post<TestResult>('/notifications/test/email', params)
  },

  testWebhook(url: string, secret?: string): Promise<TestResult> {
    return post<TestResult>('/notifications/test/webhook', { url, secret })
  }
}
