import {
  Activity,
  Check, CheckCircle2,
  ChevronRight,
  Gamepad2, HardDrive, History, LayoutDashboard, ListFilter,
  LoaderCircle, LogOut, Moon, Play,
  Settings2, Shield, ShieldAlert, Sun,
  Trash2,
  X
} from 'lucide-react'
import { useCallback, useEffect, useRef, useState } from 'react'
import {
  api, busy,
  completed,
  preview, url, type Cleanup, type Detail, type Info,
  type Job, type Journal, type Progress
} from './api'
import { Modal } from './components/Presentation'
import Login from './features/authentication/Login'
import { actions } from './features/jobs/actions'
import JobsView from './features/jobs/JobsView'
import FileDetails from './features/library/FileDetails'
import LibraryView from './features/library/LibraryView'
import { useLibrary } from './features/library/useLibrary'
import OverviewView from './features/overview/OverviewView'
import RecoveryView from './features/recovery/RecoveryView'
import SettingsView from './features/settings/SettingsView'
import type { Confirmation, Tab } from './workspace'

const tabs = [
  { name: 'Overview', icon: LayoutDashboard }, { name: 'Library', icon: Gamepad2 },
  { name: 'Changes', icon: ListFilter }, { name: 'Jobs', icon: Activity },
  { name: 'Recovery', icon: History }, { name: 'Settings', icon: Settings2 },
] as const
export default function App() {
  const [authenticated, setAuthenticated] = useState<boolean | null>(null)
  const [tab, setTab] = useState<Tab>('Overview')
  const [info, setInfo] = useState<Info>()
  const [jobs, setJobs] = useState<Job[]>([])
  const [jobId, setJobId] = useState('')
  const [detail, setDetail] = useState<Detail>()
  const [progress, setProgress] = useState<Progress | null>(null)
  const [journals, setJournals] = useState<Journal[]>([])
  const [cleanup, setCleanup] = useState<Cleanup[]>([])
  const [confirmation, setConfirmation] = useState<Confirmation>()
  const [error, setError] = useState('')
  const [notice, setNotice] = useState('')
  const [pending, setPending] = useState(false)
  const [log, setLog] = useState('')
  const [dark, setDark] = useState(() => localStorage.getItem('romchecker-theme') !== 'light')
  const watchedJob = useRef<string | null>(null)
  const active = jobs.find(busy)
  const historyJob = jobs.find(j => j.action === 'history' && completed(j))
  const cleanupJob = jobs.find(j => j.action === 'cleanup-preview' && completed(j))
  const fail = useCallback((err: unknown) => setError(err instanceof Error ? err.message : String(err)), [])
  const library = useLibrary(jobs, fail, setNotice)
  const { setResultId, summary, selected, file, setPage, setFile, setReviews, selectResults, review } = library
  const refresh = useCallback(async () => {
    const list = await api<Job[]>('/jobs')
    setJobs(list)
    return list
  }, [])
  useEffect(() => {
    const expired = () => setAuthenticated(false)
    window.addEventListener('session-expired', expired)
    api('/session').then(() => setAuthenticated(true)).catch(err => {
      setAuthenticated(false)
      if (err.status !== 401) fail(err)
    })
    return () => window.removeEventListener('session-expired', expired)
  }, [fail])
  useEffect(() => {
    document.documentElement.dataset.theme = dark ? 'dark' : 'light'
    localStorage.setItem('romchecker-theme', dark ? 'dark' : 'light')
  }, [dark])
  useEffect(() => {
    if (!authenticated) return
    Promise.all([api<Info>('/info'), refresh()]).then(([metadata, list]) => {
      setInfo(metadata); setJobId(list[0]?.id ?? '')
      setResultId(list.find(j => completed(j) && (preview(j) || j.action === 'apply'))?.id ?? '')
    }).catch(fail)
    const timer = setInterval(() => refresh().catch(fail), 5000)
    return () => clearInterval(timer)
  }, [authenticated, refresh, fail])
  useEffect(() => {
    if (!active) { setProgress(null); return }
    const events = new EventSource(url(`/jobs/${active.id}/events`))
    events.onmessage = event => {
      const data = JSON.parse(event.data) as { job: Job; progress: Progress | null }
      setProgress(data.progress)
      if (!busy(data.job)) {
        events.close()
        setJobs(previous => previous.map(job => job.id === data.job.id ? data.job : job))
        refresh().catch(fail)
      }
    }
    events.onerror = () => { /* EventSource reconnects; job-list polling remains available. */ }
    return () => events.close()
  }, [active?.id, refresh, fail])
  useEffect(() => {
    const job = jobs.find(item => item.id === watchedJob.current)
    if (!job || busy(job)) return
    watchedJob.current = null
    if (completed(job) && ['scan', 'inventory', 'workflow', 'plan', 'apply'].includes(job.action)) {
      setResultId(job.id); setPage(1); setReviews([])
      setTab(job.action === 'plan' ? 'Changes' : 'Library')
    }
    if (completed(job)) setNotice(`${actions[job.action]} finished${job.status === 'completed-with-warnings' ? ' with warnings. Review the job log.' : '.'}`)
    else if (job.error) setError(job.error)
  }, [jobs])
  useEffect(() => {
    if (!jobId || tab !== 'Jobs') return
    let alive = true
    const update = () => Promise.all([api<Detail>(`/jobs/${jobId}`),
      fetch(url(`/jobs/${jobId}/log`), { credentials: 'same-origin' }).then(async response => {
        if (!response.ok) throw new Error(`Could not load log (${response.status}).`)
        return response.text()
      })]).then(([data, output]) => { if (alive) { setDetail(data); setLog(output) } }).catch(fail)
    update(); const timer = setInterval(update, 2000)
    return () => { alive = false; clearInterval(timer) }
  }, [jobId, tab, fail])
  useEffect(() => {
    if (historyJob) api<Journal[]>(`/jobs/${historyJob.id}/artifacts/history.json`).then(setJournals).catch(fail)
  }, [historyJob?.id, fail])
  useEffect(() => {
    if (cleanupJob) api<Cleanup[]>(`/jobs/${cleanupJob.id}/artifacts/cleanup.json`).then(setCleanup).catch(fail)
  }, [cleanupJob?.id, fail])
  async function start(action: string, extra: Record<string, unknown> = {}) {
    setPending(true); setError(''); setNotice('')
    try {
      const job = await api<Job>('/jobs', { method: 'POST', body: JSON.stringify({ action, ...extra }) })
      watchedJob.current = job.id
      setJobs(previous => [job, ...previous]); setJobId(job.id); setTab('Jobs'); setConfirmation(undefined)
    } catch (err) { fail(err) }
    finally { setPending(false) }
  }
  function confirm(value: Confirmation) { setError(''); setConfirmation(value) }
  if (authenticated === null) return <div className="boot"><LoaderCircle className="spin" />Connecting to ROM Checker...</div>
  if (!authenticated) return <Login onLogin={() => { setAuthenticated(true); setError('') }} />
  return <div className="app-shell">
    <aside className="sidebar"><a className="brand" href="#overview" onClick={() => setTab('Overview')}><span className="logo-mark"><Gamepad2 size={24} /></span><span>ROM<span className="brand-light">CHECKER</span><small>COLLECTION WORKSPACE</small></span></a>
      <span className="nav-label">WORKSPACE</span><nav aria-label="Main navigation">{tabs.map(({ name, icon: Icon }) =>
        <button key={name} aria-label={name} title={name} className={tab === name ? 'nav-item selected' : 'nav-item'} aria-current={tab === name ? 'page' : undefined} onClick={() => setTab(name)}><Icon size={19} /><span>{name}</span>{name === 'Jobs' && active && <span className="live-dot" />}</button>)}</nav>
      <div className="sidebar-bottom"><div className="storage-label"><HardDrive size={18} /><strong>Your storage. Your files.</strong></div><p>Self-hosted. No ROM uploads.<br />Online checks use hashes and metadata.</p>
        <div className="row spread"><span className="version">v{info?.version ?? '...'}</span></div></div>
    </aside>
    <div className="main-shell"><header className="topbar"><div className="breadcrumb">Workspace <ChevronRight size={14} /><strong>{tab}</strong></div>
      <div className="row"><span className="server-status"><span className="live-dot" />Self-hosted</span><button className="icon-button" onClick={() => setDark(!dark)} aria-label={dark ? 'Use light theme' : 'Use dark theme'}>{dark ? <Sun size={18} /> : <Moon size={18} />}</button><button className="icon-button" aria-label="Sign out" onClick={() => api('/logout', { method: 'POST' }).then(() => setAuthenticated(false)).catch(fail)}><LogOut size={18} /></button></div></header>
      <main className="content">
        {error && <div className="notice error" role="alert"><ShieldAlert size={19} /><span>{error}</span><button className="icon-button" aria-label="Dismiss error" onClick={() => setError('')}><X size={17} /></button></div>}
        {notice && <div className="notice success" role="status"><CheckCircle2 size={18} /><span>{notice}</span><button className="icon-button" aria-label="Dismiss notification" onClick={() => setNotice('')}><X size={17} /></button></div>}
        <div className="page-heading"><div><span className="eyebrow">YOUR COLLECTION, UNDERSTOOD</span><h1>{tab === 'Overview' ? 'Library overview' : tab === 'Changes' ? 'Review your next move' : tab === 'Recovery' ? 'History & recovery' : tab === 'Settings' ? 'Make it your workspace' : tab}</h1>
          <p>{tab === 'Overview' ? 'A clear picture of your ROMs. A safer way to keep them organized.' : tab === 'Library' ? 'Explore the evidence behind every file in your collection.' : tab === 'Changes' ? 'Nothing moves until you approve a completed preview.' : tab === 'Jobs' ? 'Follow each operation, from the first check to the last file.' : tab === 'Recovery' ? 'Recover journaled changes or reclaim verified archive space.' : 'Configure verification, sorting, and file-handling safeguards.'}</p></div>
          {tab !== 'Settings' && <button className="primary" disabled={!!active || pending} onClick={() => start('scan')}><Play size={16} />Check library</button>}</div>
        {tab === 'Overview' && <OverviewView info={info} summary={summary} selected={selected} jobs={jobs} active={active} progress={progress} pending={pending} start={start} confirm={confirm} setTab={setTab} setJobId={setJobId} />}
        {(tab === 'Library' || tab === 'Changes') && <LibraryView tab={tab} library={library} jobs={jobs} active={active} pending={pending} start={start} confirm={confirm} />}
        {tab === 'Jobs' && <JobsView jobs={jobs} jobId={jobId} detail={detail} log={log} setJobId={setJobId} selectResults={selectResults} setTab={setTab} refresh={refresh} fail={fail} />}
        {tab === 'Recovery' && <RecoveryView journals={journals} cleanup={cleanup} cleanupJob={cleanupJob} active={active} pending={pending} start={start} confirm={confirm} />}
        {tab === 'Settings' && <SettingsView info={info} fail={fail} saved={() => setNotice('Settings saved. New jobs use these settings; existing previews keep their original configuration.')} />}
        <footer className="page-footer"><span>ROM CHECKER <span className="muted">/ A little more order. A lot more clarity.</span></span><span className="row"><Shield size={14} />Preview first. Apply with confidence.</span></footer>
      </main>
    </div>
    {confirmation && <Modal title={confirmation.title} close={() => !pending && setConfirmation(undefined)}><div className={`confirmation-icon ${confirmation.dangerous ? 'danger' : ''}`}>{confirmation.dangerous ? <Trash2 size={28} /> : <Shield size={28} />}</div><p>{confirmation.message}</p>{error && <div className="notice error" role="alert">{error}</div>}<div className="dialog-actions"><button disabled={pending} onClick={() => setConfirmation(undefined)}>Cancel</button><button className={confirmation.dangerous ? 'danger-button' : 'primary'} disabled={pending} onClick={() => start(confirmation.action, { sourceId: confirmation.sourceId, journal: confirmation.journal, confirm: true })}>{pending ? <LoaderCircle size={17} className="spin" /> : <Check size={17} />}Confirm</button></div></Modal>}
    {file && <FileDetails file={file} selected={selected} close={() => setFile(undefined)} review={review} />}
  </div>
}
