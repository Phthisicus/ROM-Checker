const configuredBase = document.querySelector<HTMLMetaElement>('meta[name="romchecker-base"]')?.content ?? ''
export const base = configuredBase.startsWith('__') ? '' : configuredBase
export const url = (path: string) => `${base}/api${path}`

export class ApiError extends Error {
  constructor(message: string, public status: number) { super(message) }
}
export async function api<T>(path: string, init: RequestInit = {}): Promise<T> {
  const response = await fetch(url(path), {
    ...init, credentials: 'same-origin',
    headers: { 'Content-Type': 'application/json', 'X-RomChecker': '1', ...init.headers },
  })
  if (!response.ok) {
    const body = await response.text()
    let message = response.status === 429 ? 'Too many sign-in attempts. Try again in a minute.' : `Request failed (${response.status}).`
    if (body) {
      try { const data = JSON.parse(body); message = data.error ?? data.detail ?? message }
      catch { message = body.slice(0, 300) }
    }
    if (response.status === 401 && path !== '/login') window.dispatchEvent(new Event('session-expired'))
    throw new ApiError(message, response.status)
  }
  if (response.status === 204) return undefined as T
  return response.json() as Promise<T>
}
export type Settings = {
  console: string; layout: string; datFolder: string; sortByCategory: boolean; defenderScan: boolean
  strict: boolean; requireDatMatch: boolean; moveBSandST: boolean; protectAppFolders: boolean
  moveCompanions: boolean; keepGameFolders: boolean; duplicateMode: string; cleanEmptyFolders: boolean
  useFolderHints: boolean; hashLimitMB: number; autoDat: boolean; hasheous: string; identifyUnknown: boolean
  retailOnly: boolean; onlineCheck: string; resumeScans: boolean; archiveMaxMB: number
  archiveMaxEntries: number; archiveMaxDepth: number; archiveTimeoutSeconds: number
}
export type Info = { name: string; version: string; commit: string; library: string; pathBase: string; platform: string; antivirus: string }
export type Job = {
  id: string; action: string; status: string; created: string; finished?: string; error?: string
  request: { sourceId?: string; journal?: string; batchId?: string; selection?: string[]; organize?: boolean }; settings: Settings
}
export type Progress = {
  Task: string; Phase: string; Done: number; Total: number; Percent: number; Unit: string
  Current: string; Detail: string; Elapsed: number; SecondsRemaining: number
}
export type Summary = { Count: number; Planned: number; Warnings: number; Counters?: Record<string, number>; ServiceIssues?: string[] }
export type Detail = { job: Job; progress: Progress | null; summary: Summary | null }
export type Result = {
  FileName: string; FullName: string; Folder: string; Console: string; Category: string; Reason: string
  Threats: string; Notes: string; Authenticity: string; IntegrityStatus: string; AntivirusStatus: string
  MalwareStatus: string; DatStrength: string; Security: string; Sources: string; Libraries: string
  Year: string; Publisher: string; Header: string; SHA256: string; SHA1: string; MD5: string; CRC32: string
  Length: number; Target: string; Action: string; DupOf: string; SetId: string; CheckedUtc: string; AntivirusCheckedUtc: string
  Reviewable: boolean
}
export type ResultsPage = { total: number; page: number; size: number; categories: string[]; consoles: string[]; items: Result[] }
export type Journal = { Name: string; Modified: string; Entries: number }
export type Cleanup = { Path: string; OriginalPath: string; SHA256: string; Bytes: number; Eligible: boolean; Reason: string }
export type Review = { path: string; decision: string }
export const busy = (job?: Job) => !!job && ['queued', 'running', 'cancelling'].includes(job.status)
export const completed = (job?: Job) => !!job && ['completed', 'completed-with-warnings'].includes(job.status)
export const preview = (job: Job) => completed(job) && ['scan', 'inventory', 'workflow', 'plan'].includes(job.action)
export const bytes = (value: number) => {
  if (!value) return '0 B'
  const index = Math.min(Math.floor(Math.log(value) / Math.log(1024)), 4)
  return `${(value / 1024 ** index).toFixed(index ? 1 : 0)} ${['B', 'KB', 'MB', 'GB', 'TB'][index]}`
}
export const label = (value: string) => value.replaceAll('_', ' ').replaceAll('-', ' ')
export const date = (value?: string) => value ? new Date(value).toLocaleString() : 'Not yet'
