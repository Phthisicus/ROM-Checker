import {
  Activity, ArrowRight, ArrowUpRight, Check,
  ChevronRight,
  FileCheck2, FolderOpen, Gamepad2,
  History,
  ListFilter,
  Shield, ShieldAlert
} from 'lucide-react'
import {
  date,
  type Info,
  type Job,
  type Progress,
  type Summary
} from '../../api'

import { Badge, Empty, ProgressCard } from '../../components/Presentation'
import type { ConfirmAction, StartJob, Tab } from '../../workspace'
import { actions } from '../jobs/actions'

type Props = { scope?: string; info?: Info; summary: Summary | null; selected?: Job; jobs: Job[]; active?: Job; progress: Progress | null; pending: boolean; start: StartJob; confirm: ConfirmAction; setTab: (tab: Tab) => void; setJobId: (id: string) => void }
export default function OverviewView({ scope, info, summary, selected, jobs, active, progress, pending, start, confirm, setTab, setJobId }: Props) {
  return <>
          <div className="library-location"><FolderOpen size={18} /><span className="mono truncate" title={scope ?? info?.library}>{scope ?? info?.library ?? 'Loading library...'}</span><span className="badge neutral">{scope ? 'Batch working copy' : 'Mounted library'}</span></div>
          <div className="stats-grid">{[
            { title: 'Files in last result', value: summary?.Count ?? 0, icon: Gamepad2, sub: selected ? date(selected.created) : 'Start your first check' },
            { title: 'Planned moves', value: summary?.Planned ?? 0, icon: ListFilter, sub: 'Review before applying' },
            { title: 'Recorded warnings', value: summary?.Warnings ?? 0, icon: ShieldAlert, sub: 'See findings and job logs' },
            { title: 'Saved operations', value: jobs.length, icon: History, sub: 'Latest 200 jobs retained in view' },
          ].map(({ title, value, icon: Icon, sub }) => <div className="stat" key={title}><div className="row spread"><span>{title}</span><Icon size={20} /></div><strong>{value.toLocaleString()}</strong><small>{sub}</small></div>)}</div>
          {active && <ProgressCard job={active} progress={progress} />}
          <div className="overview-grid"><section className="panel"><div className="section-heading"><div><h2>A place for every game</h2><p>Start with evidence. Make changes with confidence.</p></div><Shield className="accent" size={26} /></div>
            <div className="workflow-list">{[
              { title: 'Check & build a preview', text: 'Analyze content, verify hashes, find duplicates, and preview sorting.', action: 'scan', icon: FileCheck2 },
              { title: 'Organize without checking', text: 'Fast inventory using extensions and folders. Validity stays unknown.', action: 'inventory', icon: ListFilter },
              { title: 'Unpack & check', text: 'Unpack eligible archives, then check. Sorting still needs approval.', action: 'workflow', icon: FolderOpen },
            ].map(({ title, text, action, icon: Icon }) => <button className="workflow" disabled={!!active || pending} key={action} onClick={() => action === 'workflow' ? confirm({ title: 'Unpack & check library?', message: 'Eligible archives will be extracted and originals kept in recovery storage. Your configured protection settings are used. A scan and sorting preview follow; no sorting is applied automatically.', action }) : start(action)}><span className="workflow-icon"><Icon size={22} /></span><span><strong>{title}</strong><small>{text}</small></span><ArrowUpRight size={19} /></button>)}</div>
            <button className="text-button" disabled={!!active || pending} onClick={() => confirm({ title: 'Unpack archives only?', message: 'Extract eligible archives with your configured protection and resource limits. Originals are kept for recovery. This action does not scan the whole library or sort files.', action: 'unpack' })}>Unpack archives only <ArrowRight size={15} /></button>
          </section><section className="panel evidence"><span className="eyebrow">BUILT AROUND EVIDENCE</span><h2>Verification.<br />{' '}Not guesswork.</h2><p>Authenticity, integrity, antivirus completion, and malware indicators are independent findings.</p><div className="evidence-tags"><span><Check size={15} />Content & headers</span><span><Check size={15} />DAT references & hashes</span><span><Check size={15} />Journaled recovery</span></div><div className="notice subtle"><ShieldAlert size={18} /><span>No detections is not a guarantee of safety. Always review incomplete protection.</span></div></section></div>
          <section className="panel"><div className="section-heading"><div><h2>Recent activity</h2><p>Your latest operations at a glance.</p></div><button className="text-button" onClick={() => setTab('Jobs')}>All jobs <ArrowRight size={15} /></button></div>
            {jobs.length ? jobs.slice(0, 5).map(job => <button className="activity-row" key={job.id} onClick={() => { setJobId(job.id); setTab('Jobs') }}><span className="activity-icon"><Activity size={18} /></span><span><strong>{actions[job.action]}</strong><small>{date(job.created)}</small></span><Badge value={job.status} /><ChevronRight size={16} /></button>) : <Empty title="Your workspace is ready">Run your first library check to see results and activity here.</Empty>}</section>
        </>
}
