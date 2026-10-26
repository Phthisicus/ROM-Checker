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
import StorageView from './features/storage/StorageView'
import CollectionsView from './features/storage/CollectionsView'
import type { Confirmation, Tab } from './workspace'

const tabs = [
  { name: 'Overview', icon: LayoutDashboard }, { name: 'Library', icon: Gamepad2 },
  { name: 'Changes', icon: ListFilter }, { name: 'Jobs', icon: Activity },
  { name: 'Recovery', icon: History }, { name: 'Settings', icon: Settings2 },
  { name: 'Storage', icon: HardDrive },
] as const
export default function App() {
  const [authenticated, setAuthenticated] = useState<boolean | null>(null)
  const [tab, setTab] = useState<Tab>('Storage')
  const [expert, setExpert] = useState(() => localStorage.getItem('romchecker-expert') === 'true')
  const [legacyStorage, setLegacyStorage] = useState(false)
  const [info, setInfo] = useState<Info>()
  const [jobs, setJobs] = useState<Job[]>([])
  const [batchId, setBatchId] = useState(() => sessionStorage.getItem('romchecker-collection') ?? '')
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
  useEffect(() => { sessionStorage.setItem('romchecker-collection', batchId) }, [batchId])
  const historyJob = jobs.find(j => j.action === 'history' && completed(j) && (j.request.batchId ?? '') === batchId)
  const cleanupJob = jobs.find(j => j.action === 'cleanup-preview' && completed(j) && (j.request.batchId ?? '') === batchId)
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
    if (['detect', 'verify'].includes(job.action)) {
      if (!completed(job) && job.error) setError(job.error)
      return
    }
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
    let alive = true
    setJournals([])
    if (historyJob) api<Journal[]>(`/jobs/${historyJob.id}/artifacts/history.json`).then(value => { if (alive) setJournals(value) }).catch(fail)
    return () => { alive = false }
  }, [historyJob?.id, fail])
  useEffect(() => {
    let alive = true
    setCleanup([])
    if (cleanupJob) api<Cleanup[]>(`/jobs/${cleanupJob.id}/artifacts/cleanup.json`).then(value => { if (alive) setCleanup(value) }).catch(fail)
    return () => { alive = false }
  }, [cleanupJob?.id, fail])
  async function start(action: string, extra: Record<string, unknown> = {}) {
    setPending(true); setError(''); setNotice('')
    try {
      const source = typeof extra.sourceId === 'string' ? jobs.find(job => job.id === extra.sourceId) : undefined
      const scope = source ? source.request.batchId : typeof extra.batchId === 'string' ? extra.batchId : batchId || undefined
      const job = await api<Job>('/jobs', { method: 'POST', body: JSON.stringify({ action, ...extra, batchId: scope }) })
      setBatchId(job.request.batchId ?? '')
      watchedJob.current = job.id
      setJobs(previous => [job, ...previous]); setJobId(job.id); setTab(['detect', 'verify'].includes(action) ? 'Storage' : 'Jobs'); setConfirmation(undefined)
    } catch (err) { fail(err) }
    finally { setPending(false) }
  }
  function confirm(value: Confirmation) { setError(''); setConfirmation(value) }
  if (authenticated === null) return <div className="boot"><LoaderCircle className="spin" />Connecting to ROM Checker...</div>
  if (!authenticated) return <Login onLogin={() => { setAuthenticated(true); setError('') }} />
  return <div className="app-shell">
    <aside className="sidebar"><a className="brand" href="#collections" onClick={() => setTab('Storage')}><span className="logo-mark"><Gamepad2 size={24} /></span><span>ROM<span className="brand-light">CHECKER</span><small>COLLECTION WORKSPACE</small></span></a>
      <span className="nav-label">WORKSPACE</span><nav aria-label="Main navigation">{[...tabs.filter(item => item.name === 'Storage'), ...tabs.filter(item => ['Jobs', 'Settings'].includes(item.name)), ...tabs.filter(item => expert && !['Storage', 'Jobs', 'Settings'].includes(item.name))].map(({ name, icon: Icon }) => {
        const title = ({ Storage: 'Collections', Jobs: 'Activity', Recovery: 'Undo changes', Overview: 'Server library', Library: 'Detailed results', Changes: 'Move previews', Settings: 'Settings' })[name]
        return <button key={name} aria-label={title} title={title} className={tab === name ? 'nav-item selected' : 'nav-item'} aria-current={tab === name ? 'page' : undefined} onClick={() => { setTab(name); setLegacyStorage(false) }}><Icon size={19} /><span>{title}</span>{name === 'Jobs' && active && <span className="live-dot" />}</button>
      })}</nav>
      <button className="nav-item" aria-pressed={expert} onClick={() => { const value = !expert; setExpert(value); localStorage.setItem('romchecker-expert', String(value)); if (!value) { setLegacyStorage(false); setTab('Storage') } }}><Settings2 size={18} /><span>Expert workspace {expert ? 'on' : 'off'}</span></button>
      <div className="sidebar-bottom"><div className="storage-label"><HardDrive size={18} /><strong>Your storage. Your files.</strong></div><p>Self-hosted folder & SMB imports.<br />Online checks use hashes and metadata.</p>
        <div className="row spread"><span className="version">v{info?.version ?? '...'}</span></div></div>
    </aside>
    <div className="main-shell"><header className="topbar"><div className="breadcrumb">Workspace <ChevronRight size={14} /><strong>{tab === 'Storage' ? 'Collections' : tab === 'Jobs' ? 'Activity' : tab === 'Recovery' ? 'Undo changes' : tab}</strong></div>
      <div className="row"><span className="server-status"><span className="live-dot" />Self-hosted</span><button className="icon-button" onClick={() => setDark(!dark)} aria-label={dark ? 'Use light theme' : 'Use dark theme'}>{dark ? <Sun size={18} /> : <Moon size={18} />}</button><button className="icon-button" aria-label="Sign out" onClick={() => api('/logout', { method: 'POST' }).then(() => setAuthenticated(false)).catch(fail)}><LogOut size={18} /></button></div></header>
      <main className="content">
        {batchId && tab !== 'Storage' && <div className="notice subtle batch-scope"><HardDrive size={18} /><span>Current collection selected. Detailed results and recovery use this collection.</span><button onClick={() => { setBatchId(''); setTab('Overview') }}>Use server library instead</button></div>}
        {error && <div className="notice error" role="alert"><ShieldAlert size={19} /><span>{error}</span><button className="icon-button" aria-label="Dismiss error" onClick={() => setError('')}><X size={17} /></button></div>}
        {notice && <div className="notice success" role="status"><CheckCircle2 size={18} /><span>{notice}</span><button className="icon-button" aria-label="Dismiss notification" onClick={() => setNotice('')}><X size={17} /></button></div>}
        <div className="page-heading"><div><span className="eyebrow">YOUR COLLECTION, UNDERSTOOD</span><h1>{tab === 'Storage' ? 'Your collections' : tab === 'Jobs' ? 'Activity' : tab === 'Overview' ? 'Server library' : tab === 'Changes' ? 'Review your next move' : tab === 'Recovery' ? 'Undo changes & recovery' : tab === 'Settings' ? 'Make it your workspace' : tab}</h1>
          <p>{tab === 'Overview' ? 'A clear picture of your ROMs. A safer way to keep them organized.' : tab === 'Library' ? 'Explore the evidence behind every file in your collection.' : tab === 'Changes' ? 'Nothing moves until you approve a completed preview.' : tab === 'Jobs' ? 'Follow each operation, from the first check to the last file.' : tab === 'Recovery' ? 'Recover journaled changes or reclaim verified archive space.' : tab === 'Storage' ? 'Import folders or SMB files, choose processing features, and download your results.' : 'Configure verification, sorting, and file-handling safeguards.'}</p></div>
          {expert && tab !== 'Settings' && tab !== 'Storage' && <button className="primary" disabled={!!active || pending} onClick={() => start('scan')}><Play size={16} />Check library</button>}
          {expert && tab === 'Storage' && <button onClick={() => setLegacyStorage(!legacyStorage)}>{legacyStorage ? 'Guided collections' : 'Advanced storage & extraction'}</button>}</div>
        {tab === 'Overview' && <OverviewView scope={batchId ? `Storage batch ${batchId}` : undefined} info={info} summary={summary} selected={selected} jobs={jobs} active={active} progress={progress} pending={pending} start={start} confirm={confirm} setTab={setTab} setJobId={setJobId} />}
        {(tab === 'Library' || tab === 'Changes') && <LibraryView tab={tab} library={library} jobs={jobs} active={active} pending={pending} start={start} confirm={confirm} />}
        {tab === 'Jobs' && <JobsView jobs={jobs} jobId={jobId} detail={detail} log={log} setJobId={setJobId} selectResults={selectResults} setTab={setTab} refresh={refresh} fail={fail} openCollection={id => { setBatchId(id); setLegacyStorage(false); setTab('Storage') }} />}
        {tab === 'Recovery' && <RecoveryView journals={journals} cleanup={cleanup} cleanupJob={cleanupJob} active={active} pending={pending} start={start} confirm={confirm} />}
        {tab === 'Settings' && <SettingsView info={info} fail={fail} saved={() => setNotice('Settings saved. New jobs use these settings; existing previews keep their original configuration.')} />}
        {tab === 'Storage' && (legacyStorage ? <StorageView batchId={batchId} select={setBatchId} start={start} active={!!active || pending} fail={fail} /> : <CollectionsView batchId={batchId} select={setBatchId} start={start} jobs={jobs} progress={progress} fail={fail} recovery={() => { setExpert(true); setTab('Recovery') }} />)}
        <footer className="page-footer"><span>ROM CHECKER <span className="muted">/ A little more order. A lot more clarity.</span></span><span className="row"><Shield size={14} />Originals preserved. Findings explained.</span></footer>
      </main>
    </div>
    {confirmation && <Modal title={confirmation.title} close={() => !pending && setConfirmation(undefined)}><div className={`confirmation-icon ${confirmation.dangerous ? 'danger' : ''}`}>{confirmation.dangerous ? <Trash2 size={28} /> : <Shield size={28} />}</div><p>{confirmation.message}</p>{error && <div className="notice error" role="alert">{error}</div>}<div className="dialog-actions"><button disabled={pending} onClick={() => setConfirmation(undefined)}>Cancel</button><button className={confirmation.dangerous ? 'danger-button' : 'primary'} disabled={pending} onClick={() => start(confirmation.action, { sourceId: confirmation.sourceId, journal: confirmation.journal, confirm: true })}>{pending ? <LoaderCircle size={17} className="spin" /> : <Check size={17} />}Confirm</button></div></Modal>}
    {file && <FileDetails file={file} selected={selected} close={() => setFile(undefined)} review={review} />}
  </div>
}
