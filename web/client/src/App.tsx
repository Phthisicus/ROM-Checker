import {
  Activity,
  Check,
  Gamepad2, HardDrive, History, LayoutDashboard, ListFilter, Link2,
  LogOut, Menu, Moon, PanelLeftClose, PanelLeftOpen, Play,
  Settings2, Shield, Sun,
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
import { Button, LoadingState, NavigationItem, Notice } from './design-system/components'
import Breadcrumbs from './components/Breadcrumbs'
import Login from './features/authentication/Login'
import { actions } from './features/jobs/actions'
import JobsView from './features/jobs/JobsView'
import ActivitySummary from './features/jobs/ActivitySummary'
import FileDetails from './features/library/FileDetails'
import LibraryView from './features/library/LibraryView'
import { useLibrary } from './features/library/useLibrary'
import OverviewView from './features/overview/OverviewView'
import RecoveryView from './features/recovery/RecoveryView'
import SettingsView from './features/settings/SettingsView'
import StorageView from './features/storage/StorageView'
import CollectionsView from './features/storage/CollectionsView'
import CatalogView from './features/library/CatalogView'
import ConnectionsView from './features/integrations/ConnectionsView'
import type { Confirmation } from './workspace'
import { navigate, useRoute } from './navigation'

const tabs = [
  { name: 'Overview', icon: LayoutDashboard }, { name: 'ExpertLibrary', icon: Gamepad2 },
  { name: 'Changes', icon: ListFilter }, { name: 'Jobs', icon: Activity },
  { name: 'Recovery', icon: History }, { name: 'Settings', icon: Settings2 },
  { name: 'Library', icon: Gamepad2 }, { name: 'Storage', icon: HardDrive }, { name: 'Integrations', icon: Link2 },
] as const
export default function App() {
  const [authenticated, setAuthenticated] = useState<boolean | null>(null)
  const { tab, integration } = useRoute()
  const setTab = navigate
  const [expert, setExpert] = useState(() => localStorage.getItem('romchecker-advanced') === 'true')
  const [menuOpen, setMenuOpen] = useState(false)
  const [collapsed, setCollapsed] = useState(() => localStorage.getItem('romchecker-sidebar') === 'collapsed')
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
  const toolTab = ['Overview', 'ExpertLibrary', 'Changes', 'Recovery'].includes(tab)
  useEffect(() => { setMenuOpen(false) }, [tab])
  useEffect(() => {
    document.title = `ROM Checker | ${tab === 'Storage' ? 'Add games' : tab === 'Jobs' ? 'Activity' : tab === 'Integrations' ? integration === 'romm' ? 'RomM settings' : 'Connections' : tab}`
    if (authenticated) document.getElementById('main-content')?.focus()
  }, [tab, integration, authenticated])
  useEffect(() => {
    if (!menuOpen) return
    const navigation = document.getElementById('workspace-navigation')
    const focusable = () => Array.from(navigation?.querySelectorAll<HTMLElement>('a, button') ?? []).filter(element => element.getClientRects().length > 0)
    focusable()[0]?.focus()
    function keydown(event: KeyboardEvent) {
      if (event.key === 'Escape') setMenuOpen(false)
      if (event.key !== 'Tab') return
      const elements = focusable()
      if (event.shiftKey && document.activeElement === elements[0]) { event.preventDefault(); elements.at(-1)?.focus() }
      else if (!event.shiftKey && document.activeElement === elements.at(-1)) { event.preventDefault(); elements[0]?.focus() }
    }
    function resize() { if (window.innerWidth > 900) setMenuOpen(false) }
    document.addEventListener('keydown', keydown)
    window.addEventListener('resize', resize)
    return () => {
      document.removeEventListener('keydown', keydown); window.removeEventListener('resize', resize)
      const opener = document.querySelector<HTMLButtonElement>('.mobile-menu')
      if (opener?.getClientRects().length) opener.focus()
    }
  }, [menuOpen])
  useEffect(() => { if (!expert && toolTab) setTab('Library') }, [expert, toolTab])
  function toggleAdvanced() {
    const value = !expert
    setExpert(value); localStorage.setItem('romchecker-advanced', String(value))
    if (!value) { setLegacyStorage(false); if (toolTab) setTab('Library') }
  }
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
      if (expert && (tab === 'Jobs' || toolTab)) setTab(job.action === 'plan' ? 'Changes' : 'ExpertLibrary')
    }
    if (completed(job)) setNotice(`${actions[job.action]} finished${job.status === 'completed-with-warnings' ? ' with warnings. Review the job log.' : '.'}`)
    else if (job.error) setError(job.error)
  }, [jobs])
  useEffect(() => {
    if (!jobId || tab !== 'Jobs') return
    let alive = true
    const update = () => Promise.all([api<Detail>(`/jobs/${jobId}`),
      expert ? fetch(url(`/jobs/${jobId}/log`), { credentials: 'same-origin' }).then(async response => {
        if (!response.ok) throw new Error(`Could not load log (${response.status}).`)
        return response.text()
      }) : Promise.resolve('')]).then(([data, output]) => { if (alive) { setDetail(data); setLog(output) } }).catch(fail)
    update(); const timer = setInterval(update, 2000)
    return () => { alive = false; clearInterval(timer) }
  }, [jobId, tab, expert, fail])
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
  if (authenticated === null) return <LoadingState className="boot">Connecting to ROM Checker...</LoadingState>
  if (!authenticated) return <Login onLogin={() => { setAuthenticated(true); setError('') }} />
  const title = ({ Library: 'Library', Storage: 'Add games', Jobs: 'Activity', Settings: 'Settings', Integrations: 'Connections', Overview: 'Server tools', ExpertLibrary: 'Detailed results', Changes: 'Move previews', Recovery: 'Recovery' })[tab]
  return <div className={`app-shell redesigned ${collapsed ? 'sidebar-collapsed' : ''} ${menuOpen ? 'menu-open' : ''}`}>
    <a className="skip-link" href="#main-content" onClick={event => { event.preventDefault(); document.getElementById('main-content')?.focus() }}>Skip to content</a>
    {menuOpen && <button className="navigation-scrim" aria-label="Close navigation" onClick={() => setMenuOpen(false)} />}
    <aside className="sidebar" id="workspace-navigation"><a className="brand" aria-label="ROM Checker home" href="#/library"><span className="logo-mark"><Gamepad2 size={24} /></span><span className="brand-copy">ROM<span className="brand-light">CHECKER</span><small>Your collection, at home.</small></span></a>
      <button className="icon-button mobile-nav-close" aria-label="Close navigation" onClick={() => setMenuOpen(false)}><X size={20} /></button>
      <span className="nav-label">COLLECTION</span><nav aria-label="Main navigation">{tabs.filter(item => ['Library', 'Storage', 'Jobs', 'Settings'].includes(item.name)).sort((a, b) => ['Library', 'Storage', 'Jobs', 'Settings'].indexOf(a.name) - ['Library', 'Storage', 'Jobs', 'Settings'].indexOf(b.name)).map(({ name, icon: Icon }) => {
        const label = ({ Library: 'Library', Storage: 'Add games', Jobs: 'Activity', Settings: 'Settings', Overview: '', ExpertLibrary: '', Changes: '', Recovery: '', Integrations: '' })[name]
        const selected = tab === name || name === 'Settings' && tab === 'Integrations'
        return <NavigationItem key={name} aria-label={label} title={label} current={selected} onClick={() => { setTab(name); setLegacyStorage(false) }}><Icon size={20} aria-hidden="true" /><span>{label}</span>{name === 'Jobs' && active && <span className="live-dot" />}</NavigationItem>
      })}</nav>
      {expert && <><span className="nav-label tools-label">TOOLS</span><nav aria-label="Advanced tools">{tabs.filter(item => ['Overview', 'ExpertLibrary', 'Changes', 'Recovery'].includes(item.name)).map(({ name, icon: Icon }) => <NavigationItem key={name} aria-label={name === 'Overview' ? 'Server tools' : name === 'ExpertLibrary' ? 'Detailed results' : name === 'Changes' ? 'Move previews' : 'Recovery'} title={name} current={tab === name} onClick={() => setTab(name)}><Icon size={20} aria-hidden="true" /><span>{name === 'Overview' ? 'Server tools' : name === 'ExpertLibrary' ? 'Detailed results' : name === 'Changes' ? 'Move previews' : 'Recovery'}</span></NavigationItem>)}</nav></>}
      <div className="sidebar-bottom"><button className="advanced-switch" role="switch" aria-label="Advanced mode" aria-checked={expert} title="Advanced mode" onClick={toggleAdvanced}><Settings2 size={18} /><span>Advanced mode</span><i aria-hidden="true" className={expert ? 'switch-track on' : 'switch-track'} /></button>
        <button className="collapse-navigation icon-button" aria-label={collapsed ? 'Expand sidebar' : 'Collapse sidebar'} onClick={() => { setCollapsed(!collapsed); localStorage.setItem('romchecker-sidebar', collapsed ? 'expanded' : 'collapsed') }}>{collapsed ? <PanelLeftOpen size={19} /> : <PanelLeftClose size={19} />}<span>Collapse sidebar</span></button>
        <div className="row spread"><span className="version" data-frontend-version={__APP_VERSION__}>v{info?.version ?? '...'}{info?.buildNumber ? ` · Build ${info.buildNumber}` : ''}</span></div></div>
    </aside>
    <div className="main-shell" inert={menuOpen}><header className="topbar"><div className="row"><button className="icon-button mobile-menu" aria-label="Open navigation" aria-expanded={menuOpen} aria-controls="workspace-navigation" onClick={() => setMenuOpen(!menuOpen)}><Menu size={22} /></button><Breadcrumbs tab={tab} integration={integration} /></div>
      <div className="row"><span className="server-status"><span className="live-dot" />Self-hosted</span><button className="icon-button" onClick={() => setDark(!dark)} aria-label={dark ? 'Use light theme' : 'Use dark theme'}>{dark ? <Sun size={18} /> : <Moon size={18} />}</button><button className="icon-button" aria-label="Sign out" onClick={() => api('/logout', { method: 'POST' }).then(() => setAuthenticated(false)).catch(fail)}><LogOut size={18} /></button></div></header>
      <main id="main-content" className="content" tabIndex={-1}>
        {batchId && expert && ['Overview', 'ExpertLibrary', 'Changes', 'Recovery'].includes(tab) && <div className="notice subtle batch-scope"><HardDrive size={18} /><span>Expert tools are scoped to the selected import. Your normal Library always includes all imports.</span><button onClick={() => { setBatchId(''); setTab('Overview') }}>Use server scope</button></div>}
        {error && <Notice tone="danger" dismissLabel="Dismiss error" onDismiss={() => setError('')}>{error}</Notice>}
        {notice && <Notice tone="success" onDismiss={() => setNotice('')}>{notice}</Notice>}
        <div className="page-heading"><div><h1>{tab === 'Integrations' && integration === 'romm' ? 'RomM settings' : title}</h1>
          <p>{tab === 'Library' ? 'A home for every game.' : tab === 'Integrations' ? integration === 'romm' ? 'Manage your RomM connection and synchronization.' : 'Choose an integration to configure its connection and settings.' : tab === 'Changes' ? 'Review before anything moves.' : tab === 'Jobs' ? 'Your checks and transfers, without the noise.' : tab === 'Recovery' ? 'Review and recover recorded changes.' : tab === 'Storage' ? 'From your files to your collection. Originals stay protected.' : 'Make this workspace yours.'}</p></div>
          {expert && ['Overview', 'ExpertLibrary', 'Changes', 'Recovery'].includes(tab) && <button className="primary" disabled={!!active || pending} onClick={() => start('scan')}><Play size={16} />Check library</button>}
          {expert && tab === 'Storage' && <button onClick={() => setLegacyStorage(!legacyStorage)}>{legacyStorage ? 'Guided imports' : 'Advanced storage & extraction'}</button>}</div>
        {expert && tab === 'Overview' && <OverviewView scope={batchId ? `Storage batch ${batchId}` : undefined} info={info} summary={summary} selected={selected} jobs={jobs} active={active} progress={progress} pending={pending} start={start} confirm={confirm} setTab={setTab} setJobId={setJobId} />}
        {tab === 'Library' && <CatalogView advanced={expert} activity={() => setTab('Jobs')} fail={fail} imports={() => { setBatchId(''); setTab('Storage') }} jobs={jobs} active={active} progress={progress} changed={refresh} />}
        {(tab === 'Settings' || tab === 'Integrations') && <nav className="settings-tabs" aria-label="Settings sections"><button aria-current={tab === 'Settings' ? 'page' : undefined} onClick={() => setTab('Settings')}>Preferences & server</button><button aria-current={tab === 'Integrations' ? 'page' : undefined} onClick={() => setTab('Integrations')}><Link2 size={16} />Connections</button></nav>}
        {tab === 'Integrations' && <ConnectionsView integration={integration} advanced={expert} fail={fail} />}
        {expert && (tab === 'ExpertLibrary' || tab === 'Changes') && <LibraryView tab={tab === 'ExpertLibrary' ? 'Library' : 'Changes'} library={library} jobs={jobs} active={active} pending={pending} start={start} confirm={confirm} />}
        {tab === 'Jobs' && <><ActivitySummary advanced={expert} jobs={jobs} fail={fail} /><JobsView expert={expert} jobs={jobs} jobId={jobId} detail={detail} log={log} setJobId={setJobId} selectResults={selectResults} setTab={setTab} refresh={refresh} fail={fail} openCollection={id => { setBatchId(id); setLegacyStorage(false); setTab('Storage') }} /></>}
        {expert && tab === 'Recovery' && <RecoveryView journals={journals} cleanup={cleanup} cleanupJob={cleanupJob} active={active} pending={pending} start={start} confirm={confirm} />}
        {tab === 'Settings' && <SettingsView advanced={expert} info={info} fail={fail} saved={() => setNotice('Settings saved. New jobs use these settings; existing previews keep their original configuration.')} />}
        {tab === 'Storage' && (legacyStorage ? <StorageView batchId={batchId} select={setBatchId} start={start} active={!!active || pending} fail={fail} /> : <CollectionsView advanced={expert} batchId={batchId} select={setBatchId} start={start} jobs={jobs} progress={progress} fail={fail} recovery={() => { setExpert(true); localStorage.setItem('romchecker-advanced', 'true'); setTab('Recovery') }} />)}
        <footer className="page-footer"><span>ROM CHECKER</span><span className="row"><Shield size={14} />Originals preserved. Findings explained.</span></footer>
      </main>
    </div>
    {confirmation && <Modal title={confirmation.title} closeDisabled={pending} close={() => !pending && setConfirmation(undefined)}><div className={`confirmation-icon ${confirmation.dangerous ? 'danger' : ''}`}>{confirmation.dangerous ? <Trash2 size={28} /> : <Shield size={28} />}</div><p>{confirmation.message}</p>{error && <Notice tone="danger">{error}</Notice>}<div className="dialog-actions"><Button disabled={pending} onClick={() => setConfirmation(undefined)}>Cancel</Button><Button variant={confirmation.dangerous ? 'danger' : 'primary'} loading={pending} onClick={() => start(confirmation.action, { sourceId: confirmation.sourceId, journal: confirmation.journal, confirm: true })}>{!pending && <Check size={17} aria-hidden="true" />}Confirm</Button></div></Modal>}
    {file && <FileDetails file={file} selected={selected} close={() => setFile(undefined)} review={review} />}
  </div>
}
