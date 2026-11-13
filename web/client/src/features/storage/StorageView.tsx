import { Download, FolderOpen, LoaderCircle, Network, Play, RefreshCw, Trash2, Upload } from 'lucide-react'
import { useCallback, useEffect, useRef, useState, type FormEvent } from 'react'
import { ApiError, api, bytes, type Settings } from '../../api'
import { Badge, Modal } from '../../components/Presentation'
import type { StartJob } from '../../workspace'
import { downloadUrl, uploadFolder, type Batch, type Listing, type TransferProgress } from './transfers'
import './storage.css'

type Props = { batchId: string; select: (id: string) => void; start: StartJob; active: boolean; fail: (error: unknown) => void; importOnly?: boolean }
export default function StorageView({ batchId, select, start, active, fail, importOnly = false }: Props) {
  const [enabled, setEnabled] = useState<boolean>()
  const [batches, setBatches] = useState<Batch[]>([])
  const [name, setName] = useState('')
  const [pending, setPending] = useState(false)
  const [transfer, setTransfer] = useState<TransferProgress>()
  const [message, setMessage] = useState('')
  const controller = useRef<AbortController | null>(null)
  const [listing, setListing] = useState<Listing>()
  const [tree, setTree] = useState('processed')
  const [smb, setSmb] = useState({ server: '', share: '', username: '', password: '', domain: '' })
  const [connection, setConnection] = useState(() => sessionStorage.getItem('romchecker-smb') ?? '')
  const [remote, setRemote] = useState<Listing>()
  const [paths, setPaths] = useState<string[]>([])
  const [deleteBatch, setDeleteBatch] = useState(false)
  const [processing, setProcessing] = useState(false)
  const [action, setAction] = useState('scan')
  const [settings, setSettings] = useState<Settings>()
  const [confirmed, setConfirmed] = useState(false)
  const batch = batches.find(item => item.id === batchId)
  const busy = pending || !!controller.current
  const ready = batch?.status === 'ready'
  const refresh = useCallback(async () => setBatches(await api<Batch[]>('/storage/batches')), [])
  useEffect(() => {
    api<{ enabled: boolean }>('/storage/config').then(value => {
      setEnabled(value.enabled)
      if (value.enabled) refresh().catch(fail)
    }).catch(fail)
    return () => controller.current?.abort()
  }, [refresh, fail])
  useEffect(() => {
    if (!enabled) return
    const timer = setInterval(() => refresh().catch(fail), 3000)
    return () => clearInterval(timer)
  }, [enabled, refresh, fail])
  useEffect(() => { setListing(undefined); setTransfer(undefined) }, [batchId])
  function forgetConnection() {
    setConnection(''); sessionStorage.removeItem('romchecker-smb'); setRemote(undefined); setPaths([])
  }
  async function run(work: () => Promise<void>) {
    setPending(true); setMessage('')
    try { await work(); await refresh() }
    catch (error) { if (error instanceof ApiError && error.status === 410) forgetConnection(); fail(error) }
    finally { setPending(false) }
  }
  async function create(event: FormEvent) {
    event.preventDefault()
    await run(async () => {
      const result = await api<Batch>('/storage/batches', { method: 'POST', body: JSON.stringify({ name }) })
      select(result.id); setName('')
    })
  }
  async function upload(files: File[]) {
    if (!batch || !files.length) return
    const abort = new AbortController()
    controller.current = abort
    setPending(true); setMessage('')
    try {
      await uploadFolder(batch.id, files, abort.signal, setTransfer)
      setMessage('Upload complete. Prepare the batch to create a separate processing copy.')
    } catch (error) {
      if (abort.signal.aborted) setMessage('Upload paused. Select the same folder in this batch to resume.')
      else fail(error)
    } finally { controller.current = null; setPending(false); await refresh().catch(fail) }
  }
  async function browse(path = '', page = 1, selectedTree = tree) {
    if (!batch) return
    try { setListing(await api(`/storage/batches/${batch.id}/browse?tree=${selectedTree}&path=${encodeURIComponent(path)}&page=${page}`)) }
    catch (error) { fail(error) }
  }
  async function browseRemote(path = '', page = 1, id = connection) {
    try { setRemote(await api(`/storage/smb/${id}/browse?path=${encodeURIComponent(path)}&page=${page}`)) }
    catch (error) { if (error instanceof ApiError && error.status === 410) forgetConnection(); fail(error) }
  }
  async function connect(event: FormEvent) {
    event.preventDefault()
    await run(async () => {
      const value = await api<{ id: string }>('/storage/smb', { method: 'POST', body: JSON.stringify(smb) })
      setConnection(value.id); sessionStorage.setItem('romchecker-smb', value.id)
      setSmb(previous => ({ ...previous, password: '' })); setPaths([]); await browseRemote('', 1, value.id)
    })
  }
  async function chooseProcessing() {
    try {
      const value = await api<Settings>('/settings')
      setSettings({ ...value, datFolder: '' }); setAction('scan'); setConfirmed(false); setProcessing(true)
    } catch (error) { fail(error) }
  }
  const parent = (path: string) => path.includes('/') ? path.slice(0, path.lastIndexOf('/')) : ''
  if (enabled === false) return <section className="panel"><h2>Batch storage is not configured</h2><p>Deploy the storage service and set ROMCHECKER_STORAGE_URL, ROMCHECKER_STORAGE_ROOT, and ROMCHECKER_STORAGE_TOKEN. Existing mounted-library operations remain available.</p></section>
  if (!enabled) return <p>Connecting to storage...</p>
  return <div className="storage-workspace">
    {!importOnly && <div className="notice subtle"><FolderOpen size={20} /><span>Originals are retained separately. Processing uses a copy. Nothing is automatically deleted; remove a batch explicitly when you no longer need it.</span></div>}
    <section className="panel">
      <div className="section-heading"><div><h2>{importOnly ? 'Choose an empty import' : 'Import batches'}</h2><p>One bounded transfer at a time; interrupted folder uploads can resume.</p></div><button disabled={busy} onClick={() => refresh().catch(fail)}><RefreshCw size={16} />Refresh</button></div>
      <form className="row wrap" onSubmit={create}><input aria-label={importOnly ? 'New import name' : 'New batch name'} placeholder={importOnly ? 'New import name' : 'New batch name'} value={name} maxLength={120} required onChange={e => setName(e.target.value)} /><button disabled={busy}>{importOnly ? 'Create import' : 'Create batch'}</button></form>
      <label>{importOnly ? 'Destination import' : 'Selected batch'}<select aria-label={importOnly ? 'Destination import' : 'Selected batch'} value={batchId} disabled={busy} onChange={e => select(e.target.value)}><option value="">{importOnly ? 'Choose an import' : 'Choose a batch'}</option>{batches.map(item => <option key={item.id} value={item.id}>{item.name} / {item.status} / {item.files} files</option>)}</select></label>
      {batch && <><div className="row wrap"><Badge value={batch.status} /><span>{batch.files.toLocaleString()} files / {bytes(batch.bytes)} original data</span></div>{batch.error && <div className="notice error" role="alert">{batch.error}</div>}
        {!importOnly && <div className="row wrap storage-actions">
          <label className="button"><Upload size={16} />Upload / resume folder<input aria-label="Upload ROM folder" type="file" multiple ref={element => element?.setAttribute('webkitdirectory', '')}
            disabled={busy || batch.status !== 'uploading'} onChange={e => { const files = Array.from(e.target.files ?? []); e.target.value = ''; void upload(files) }} /></label>
          <button disabled={busy || batch.prepared || !['uploading', 'failed'].includes(batch.status) || batch.files === 0}
            onClick={() => run(async () => { await api(`/storage/batches/${batch.id}/prepare`, { method: 'POST' }); setMessage('Preparing a separate processing copy. This can take time for large batches.') })}>Prepare processing copy</button>
          <button className="primary" disabled={busy || !ready || active} onClick={chooseProcessing}><Play size={16} />Choose processing features</button>
          <button className="danger-button" disabled={busy || !['uploading', 'ready', 'failed'].includes(batch.status)} onClick={() => setDeleteBatch(true)}><Trash2 size={16} />Delete batch</button>
        </div>}
        {transfer && <div role="status"><p className="mono">{transfer.file}</p><progress max={Math.max(1, transfer.totalBytes)} value={transfer.bytes} /><p>{transfer.done} / {transfer.total} files; {bytes(transfer.bytes)} / {bytes(transfer.totalBytes)}</p></div>}
        {controller.current && <button onClick={() => controller.current?.abort()}>Pause upload</button>}
        {message && <p role="status">{message}</p>}
      </>}
    </section>
    {batch && !importOnly && <section className="panel">
      <div className="section-heading"><div><h2>Browse stored ROMs</h2><p>Download a file directly or a folder as a streaming ZIP.</p></div><Download size={20} /></div>
      <div className="row wrap"><select aria-label="Storage tree" value={tree} onChange={e => { setTree(e.target.value); setListing(undefined) }}><option value="processed">Processed ROMs</option><option value="originals">Original imports</option></select>
        <button disabled={busy || ['preparing', 'processing', 'importing'].includes(batch.status)} onClick={() => browse()}>Browse root</button></div>
      {listing && <><div className="row wrap"><span className="mono">{listing.path || '/'}</span><button onClick={() => browse(parent(listing.path))}>Up</button>{tree === 'processed' && ready && <a className="button" href={downloadUrl(batch.id, listing.path)} download><Download size={16} />Download this folder as ZIP</a>}</div>
        <div className="storage-list">{listing.entries.map(entry => <div className="row spread" key={entry.path}>{entry.directory ? <button onClick={() => browse(entry.path)}><FolderOpen size={16} />{entry.name}</button> : <span>{entry.name} <small>{bytes(entry.size)}</small></span>}
          {tree === 'processed' && ready && <a className="button" href={downloadUrl(batch.id, entry.path)} download>{entry.directory ? 'Download ZIP' : 'Download'}</a>}</div>)}</div>
        <div className="row"><button disabled={listing.page === 1} onClick={() => browse(listing.path, listing.page - 1)}>Previous</button><span>Page {listing.page}</span><button disabled={!listing.more} onClick={() => browse(listing.path, listing.page + 1)}>Next</button></div>
      </>}
    </section>}
    <section className="panel">
      <div className="section-heading"><div><h2>Network share (SMB)</h2><p>Read-only imports from administrator-approved servers. Source files are never moved or deleted.</p></div><Network size={22} /></div>
      <p className="muted">Use a dedicated read-only SMB account on a trusted network or VPN. Credentials are held only for the live connection, not saved to disk. Only servers in ROMCHECKER_SMB_HOSTS are allowed.</p>
      {!connection ? <form onSubmit={connect}><div className="form-grid">{(['server', 'share', 'domain', 'username', 'password'] as const).map(key => <label key={key}>{key}<input aria-label={`SMB ${key}`} type={key === 'password' ? 'password' : 'text'} autoComplete="off"
        required={key !== 'domain'} value={smb[key]} onChange={e => setSmb({ ...smb, [key]: e.target.value })} /></label>)}</div><button disabled={busy}>Connect to SMB share</button></form>
        : <><div className="row wrap"><button disabled={busy} onClick={() => browseRemote()}>Browse SMB root</button><button disabled={busy} onClick={() => run(async () => {
          await api(`/storage/smb/${connection}`, { method: 'DELETE' }); forgetConnection()
        })}>Disconnect</button><span>{paths.length} selected item(s)</span></div>
          {remote && <><div className="row"><span className="mono">{remote.path || '/'}</span><button onClick={() => browseRemote(parent(remote.path))}>Up</button>
            <button onClick={() => setPaths(previous => [...new Set([...previous, ...remote.entries.map(entry => entry.path)])].slice(0, 1000))}>Select visible items (up to 1000)</button>
            <button onClick={() => setPaths([])}>Clear selection</button></div>
            <div className="storage-list">{remote.entries.map(entry => <div className="row" key={entry.path}><input aria-label={`Select ${entry.name}`} type="checkbox" checked={paths.includes(entry.path)} disabled={!paths.includes(entry.path) && paths.length >= 1000} onChange={e => setPaths(previous => e.target.checked ? [...previous, entry.path] : previous.filter(path => path !== entry.path))} />
              {entry.directory ? <button onClick={() => browseRemote(entry.path)}><FolderOpen size={16} />{entry.name}</button> : <span>{entry.name} / {bytes(entry.size)}</span>}</div>)}</div>
            <div className="row"><button disabled={remote.page === 1} onClick={() => browseRemote(remote.path, remote.page - 1)}>Previous</button><span>Page {remote.page}</span><button disabled={!remote.more} onClick={() => browseRemote(remote.path, remote.page + 1)}>Next</button></div></>}
          <button disabled={busy || !batch || batch.status !== 'uploading' || batch.files !== 0 || !paths.length} onClick={() => run(async () => {
            await api(`/storage/batches/${batchId}/smb-import`, { method: 'POST', body: JSON.stringify({ connectionId: connection, paths }) })
            setMessage('SMB import queued. Completed files and failures appear in the batch status.')
          })}>{importOnly ? 'Import selected files' : 'Import selection into empty batch'}</button><p className="muted">Selecting a folder imports its contents recursively and preserves share-relative paths. Create an empty import before transferring files; it joins the same Library.</p>
        </>}
    </section>
    {deleteBatch && batch && <Modal title="Permanently delete this batch?" close={() => setDeleteBatch(false)}><p>This deletes all original and processed ROMs in {batch.name}, including recovery journals. Downloads are not proof of a backup.</p>
      <button className="danger-button" disabled={pending} onClick={() => run(async () => {
        await api(`/storage/batches/${batch.id}`, { method: 'DELETE' }); select(''); setDeleteBatch(false)
      })}>Delete originals and processed files</button></Modal>}
    {processing && settings && batch && <Modal title="Choose processing features" close={() => setProcessing(false)}>
      <p>Process {batch.name}. Originals remain unchanged. Sorting always requires reviewing and explicitly applying a completed preview.</p>
      <label>Operation<select aria-label="Processing operation" value={action} onChange={e => { setAction(e.target.value); setConfirmed(false) }}><option value="scan">Verify and build sorting preview</option><option value="inventory">Inventory and sorting preview (no verification)</option><option value="unpack">Extract archives only</option><option value="workflow">Extract archives, verify and build preview</option></select></label>
      {(['defenderScan', 'autoDat', 'identifyUnknown', 'requireDatMatch', 'strict', 'retailOnly', 'resumeScans', 'moveCompanions', 'keepGameFolders', 'sortByCategory'] as const).map(key => <label className="row" key={key}><input type="checkbox" checked={settings[key]} onChange={e => setSettings({ ...settings, [key]: e.target.checked })} />{{
        defenderScan: 'Antivirus scanning', autoDat: 'Download DAT references', identifyUnknown: 'Identify unknown formats', requireDatMatch: 'Require trusted DAT match',
        strict: 'Strict validation', retailOnly: 'Retail releases only', resumeScans: 'Reuse unchanged checks', moveCompanions: 'Move companion files', keepGameFolders: 'Keep game folders intact', sortByCategory: 'Separate classifications',
      }[key]}</label>)}
      <div className="form-grid"><label>Duplicate detection<select value={settings.duplicateMode} onChange={e => setSettings({ ...settings, duplicateMode: e.target.value })}>{['Off', 'Report', 'Move'].map(value => <option key={value}>{value}</option>)}</select></label>
        <label>Online identification<select value={settings.hasheous} onChange={e => setSettings({ ...settings, hasheous: e.target.value })}>{['Off', 'Unverified', 'All'].map(value => <option key={value}>{value}</option>)}</select></label>
        <label>Online malware checks<select value={settings.onlineCheck} onChange={e => setSettings({ ...settings, onlineCheck: e.target.value })}>{['Off', 'Risky', 'Unverified', 'All'].map(value => <option key={value}>{value}</option>)}</select></label>
        <label>Sorting layout<select value={settings.layout} onChange={e => setSettings({ ...settings, layout: e.target.value })}>{['ByConsole', 'Validity', 'Emulator', 'Frontend', 'RetroArch', 'Classic'].map(value => <option key={value}>{value}</option>)}</select></label></div>
      <p className="muted">Selections apply only to this job. Limits and other defaults come from Settings. Custom DAT paths are cleared because this batch has its own isolated root. Disabled checks remain explicitly incomplete/disabled in results.</p>
      {['workflow', 'unpack'].includes(action) && <label className="row"><input type="checkbox" checked={confirmed} onChange={e => setConfirmed(e.target.checked)} />I approve extracting archives in the processing copy.</label>}
      <button className="primary" disabled={pending || active || (['workflow', 'unpack'].includes(action) && !confirmed)} onClick={async () => {
        await start(action, { batchId: batch.id, settings, confirm: confirmed }); setProcessing(false)
      }}>{pending ? <LoaderCircle className="spin" size={16} /> : <Play size={16} />}Start selected processing</button>
    </Modal>}
  </div>
}
