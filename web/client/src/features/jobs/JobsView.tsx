import {
  ArrowRight,
  Download
} from 'lucide-react'
import {
  api, busy,
  date,
  preview, url,
  type Detail,
  type Job
} from '../../api'

import { Badge, Empty, ProgressCard } from '../../components/Presentation'
import type { Tab } from '../../workspace'
import { actions } from '../jobs/actions'

type Props = { jobs: Job[]; jobId: string; detail?: Detail; log: string; setJobId: (id: string) => void; selectResults: (id: string) => void; setTab: (tab: Tab) => void; refresh: () => Promise<Job[]>; fail: (error: unknown) => void; openCollection: (id: string) => void }
export default function JobsView({ jobs, jobId, detail, log, setJobId, selectResults, setTab, refresh, fail, openCollection }: Props) {
  return <div className="jobs-grid"><section className="panel job-list"><h2>Operations</h2>{jobs.length === 0 && <Empty title="No operations yet">Start a library check to follow its progress here.</Empty>}{jobs.map(job => <button className={`job-item ${jobId === job.id ? 'selected' : ''}`} key={job.id} onClick={() => setJobId(job.id)}><strong>{actions[job.action]}</strong><small>{date(job.created)}</small><Badge value={job.status} /></button>)}</section>
          <section className="panel job-detail">{detail ? <><div className="section-heading"><div><h2>{actions[detail.job.action]}</h2><p>{date(detail.job.created)}</p></div><Badge value={detail.job.status} /></div>
            {busy(detail.job) && <ProgressCard job={detail.job} progress={detail.progress} />}
            {detail.job.error && <div className="notice error">{detail.job.error}</div>}
            {detail.summary && <div className="summary-counters">{Object.entries(detail.summary.Counters ?? {}).map(([key, value]) => <span key={key}><strong>{value}</strong>{key}</span>)}</div>}
            <div className="row wrap"><a className="button secondary" href={url(`/jobs/${jobId}/artifacts/output.log`)} download><Download size={16} />Download log</a>
              {detail.job.request.batchId && <button onClick={() => openCollection(detail.job.request.batchId!)}>Open collection <ArrowRight size={16} /></button>}
              {preview(detail.job) && <button onClick={() => { selectResults(jobId); setTab('Changes') }}>Review move plan <ArrowRight size={16} /></button>}
              {busy(detail.job) && ['scan', 'inventory', 'plan', 'history', 'undo-preview', 'cleanup-preview'].includes(detail.job.action) && <button className="danger-button" onClick={() => api(`/jobs/${jobId}/cancel`, { method: 'POST' }).then(refresh).catch(fail)}>Cancel job</button>}
            </div>{!!detail.summary?.ServiceIssues?.length && <div className="notice error" role="alert"><div><strong>Application / service issues</strong>{detail.summary.ServiceIssues.map(issue => <p key={issue}>{issue}</p>)}</div></div>}
            <details><summary>Technical details & engine output</summary><pre className="log" aria-label="Engine output">{log || 'Waiting for output...'}</pre><p className="small muted">Showing the latest 64 KB. File-changing operations cannot be cancelled midway; use recovery after completion.</p></details></> : <Empty title="Select an operation">Inspect live progress, logs, and warnings.</Empty>}</section></div>
}
