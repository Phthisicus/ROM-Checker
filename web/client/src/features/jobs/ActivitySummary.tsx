import { Activity, RefreshCw, ShieldAlert } from 'lucide-react'
import { useCallback, useEffect, useState } from 'react'
import { api, busy, date, type Job } from '../../api'
import { Badge } from '../../components/Presentation'
import { RommJobs, type RommJob } from '../integrations/RommView'

export type Verification = { id: string; createdUtc: string; status: string; error?: string; steps: { batchId: string; ids: string[]; status: string; jobId?: string }[] }
export default function ActivitySummary({ advanced, jobs, fail }: { advanced?: boolean; jobs: Job[]; fail: (error: unknown) => void }) {
  const [verifications, setVerifications] = useState<Verification[]>([])
  const [integrations, setIntegrations] = useState<RommJob[]>([])
  const [last, setLast] = useState('')
  const [error, setError] = useState('')
  const [pending, setPending] = useState(false)
  const refresh = useCallback(async () => {
    try {
      const [catalog, romm] = await Promise.all([api<Verification[]>('/catalog/verifications'), api<RommJob[]>('/romm/jobs')])
      setVerifications(catalog); setIntegrations(romm); setLast(new Date().toISOString()); setError('')
    } catch (error) { setError(error instanceof Error ? error.message : String(error)) }
  }, [])
  useEffect(() => { void refresh(); const timer = setInterval(refresh, 5000); return () => clearInterval(timer) }, [refresh])
  const running = jobs.filter(job => ['running', 'cancelling'].includes(job.status))
  const queued = jobs.filter(job => job.status === 'queued')
  const failed = jobs.filter(job => ['failed', 'interrupted'].includes(job.status))
  return <>
    <section className="panel"><div className="section-heading"><div><h2 className="row"><Activity size={19} />{advanced ? 'Workers & queue' : 'Happening now'}</h2><p>Checks and transfers continue while you browse.</p></div><button onClick={refresh}><RefreshCw size={16} />Refresh status</button></div><div className="row wrap"><Badge value={error ? 'Status unavailable' : !last ? 'Connecting' : running.length ? 'Processing' : queued.length ? 'Queued' : 'All quiet'} /><span className="small">{running.length} active · {queued.length} queued · {failed.length} failed / interrupted</span></div>{advanced && <p className="small muted">Last status response: {date(last)}. Queue state is not a worker heartbeat; check progress and errors if work is not advancing.</p>}{error && <div role="alert" className="notice error"><ShieldAlert size={18} />{error}</div>}</section>
    <section className="panel"><h2>Library checks</h2>{!verifications.length && <p className="muted">No library checks yet. Choose games or a console in Library to get started.</p>}<div className="integration-list">{verifications.map(run => <article className="integration-item" key={run.id}><div className="row spread"><strong>Checking {run.steps.reduce((sum, step) => sum + step.ids.length, 0)} files</strong><Badge value={run.status} /></div><p className="small muted">{date(run.createdUtc)} · {run.steps.filter(step => step.status === 'completed').length} of {run.steps.length} groups completed</p>{run.error && <p className="notice error">{run.error}</p>}{advanced && <details><summary>Sequential batch progress</summary>{run.steps.map(step => <p key={step.batchId} className="small break-path">{step.batchId} · {step.ids.length} ROMs · {step.status}{step.jobId ? ` · job ${step.jobId}` : ''}</p>)}</details>}</article>)}</div></section>
    <section className="panel"><h2>Integration operations</h2><RommJobs jobs={integrations} pending={pending} retry={async id => {
      setPending(true)
      try { await api(`/romm/jobs/${encodeURIComponent(id)}/retry`, { method: 'POST' }); await refresh() } catch (error) { fail(error) } finally { setPending(false) }
    }} /><p className="small muted">{integrations.some(job => ['queued', 'running'].includes(job.status)) || jobs.some(busy) ? 'Operations are in progress. This view refreshes every five seconds.' : 'No active operations.'}</p></section>
  </>
}
