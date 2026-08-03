import { get, post } from '@/utils/request'
import { setupAccessConfig } from '@/utils/setupAccess'

export interface SetupDatabaseStatus {
  driver: string
  path: string
  dsn_configured: boolean
  max_open_conns: number
  max_idle_conns: number
}

export interface SetupStatus {
  initialized: boolean
  database?: SetupDatabaseStatus
}

export interface TestDatabaseRequest {
  driver?: string
  path?: string
  dsn?: string
  host?: string
  port?: number
  database?: string
  username?: string
  password?: string
  ssl_mode?: string
  timezone?: string
  max_open_conns?: number
  max_idle_conns?: number
}

export const setupApi = {
  getStatus(): Promise<SetupStatus> {
    return get<SetupStatus>('/setup/status')
  },

  testDatabase(data: TestDatabaseRequest): Promise<{ ok: boolean }> {
    return post<{ ok: boolean }>('/setup/test-database', data, setupAccessConfig())
  },

  applyDatabase(data: TestDatabaseRequest): Promise<{
    restart_required: boolean
    config_path: string
    database: SetupDatabaseStatus
  }> {
    return post('/setup/apply', data, setupAccessConfig())
  }
}
