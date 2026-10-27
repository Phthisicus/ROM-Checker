export type Tab = 'Overview' | 'Library' | 'Changes' | 'Jobs' | 'Recovery' | 'Settings' | 'Storage' | 'ExpertLibrary' | 'Integrations'
export type Confirmation = { title: string; message: string; action: string; sourceId?: string; journal?: string; dangerous?: boolean }
export type StartJob = (action: string, extra?: Record<string, unknown>) => Promise<void>
export type ConfirmAction = (confirmation: Confirmation) => void
