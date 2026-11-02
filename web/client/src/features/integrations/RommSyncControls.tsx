import { useCallback, useEffect, useState } from 'react'
import { api, date } from '../../api'
import { Badge, Modal } from '../../components/Presentation'

export type SyncSettings = { autoImport: boolean; platformIds: number[]; refreshMetadata: boolean; intervalMinutes: number }
export const defaultSyncSettings: SyncSettings = { autoImport: false, platformIds: [], refreshMetadata: false, intervalMinutes: 60 }
type Conflict = { rommId: number; name: string; status: string; detail?: string; updated: string }
type Action = { kind: 'enable' | 'sync' } | { kind: 'keep-local' | 'import'; conflict: Conflict }
type Props = {
  settings: SyncSettings; change: (settings: SyncSettings) => void; disabled: boolean; configured: boolean
  platforms: { platformId: number; console: string }[]
}

export default function RommSyncControls({ settings, change, disabled, configured, platforms }: Props) {
  const [conflicts, setConflicts] = useState<Conflict[]>([])
  const [error, setError] = useState('')
  const [notice, setNotice] = useState('')
  const [pending, setPending] = useState(false)
  const [loaded, setLoaded] = useState(false)
  const [action, setAction] = useState<Action>()
  const refresh = useCallback(async () => {
    setConflicts(await api<Conflict[]>('/romm/conflicts')); setLoaded(true)
  }, [])
  useEffect(() => {
    const load = () => refresh().catch(error => setError(error instanceof Error ? error.message : String(error)))
    void load()
    const timer = setInterval(load, 5000)
    return () => clearInterval(timer)
  }, [refresh])
  const locked = pending || disabled
  const choices = [...new Set([...platforms.map(platform => platform.platformId), ...settings.platformIds])].filter(id => id > 0)
  async function confirm() {
    if (!action) return
    if (action.kind === 'enable') {
      change({ ...settings, autoImport: true }); setAction(undefined); return
    }
    setPending(true); setError(''); setNotice('')
    try {
      if (action.kind === 'sync') await api('/romm/sync', { method: 'POST', body: JSON.stringify({ ids: [], confirm: true }) })
      else if (action.kind === 'keep-local') await api(`/romm/conflicts/${action.conflict.rommId}`, {
        method: 'POST', body: JSON.stringify({ action: 'keep-local', confirm: true }),
      })
      else if (action.kind === 'import') await api('/romm/import', {
        method: 'POST', body: JSON.stringify({ romIds: [action.conflict.rommId], confirm: true, importChanged: true }),
      })
      setAction(undefined); await refresh()
      setNotice(action.kind === 'keep-local' ? 'Local copy kept. This remote version is ignored.' : 'Work queued. Follow RomM activity below.')
    } catch (error) { setError(error instanceof Error ? error.message : String(error)) }
    finally { setPending(false) }
  }
  return <section className="panel" style={{ marginTop: 22 }}>
    <h2>Inbound synchronization & metadata</h2>
    <p>Discover games only on the RomM platforms you explicitly select. Exact whole-game hashes prevent duplicate imports
      and import/export loops. Incoming files start unchecked; descriptive metadata never approves them.</p>
    <fieldset disabled={locked}><legend>Platforms allowed for automatic import</legend>
      {!choices.length && <p>Add and save platform mappings above before enabling inbound imports.</p>}
      {choices.map(id => <label className="catalog-check" key={id}><input type="checkbox" checked={settings.platformIds.includes(id)}
        onChange={event => change({ ...settings, platformIds: event.target.checked ? [...settings.platformIds, id] : settings.platformIds.filter(value => value !== id) })} />
        {platforms.filter(platform => platform.platformId === id).map(platform => platform.console).join(', ') || 'Unavailable mapping'} (RomM platform {id})
      </label>)}
      <label className="catalog-check"><input type="checkbox" checked={settings.autoImport}
        onChange={event => event.target.checked ? setAction({ kind: 'enable' }) : change({ ...settings, autoImport: false })} />
        Automatically import new RomM games from selected platforms</label>
      <label className="catalog-check"><input type="checkbox" checked={settings.refreshMetadata}
        onChange={event => change({ ...settings, refreshMetadata: event.target.checked })} />
        Refresh linked metadata and detect conflicts on a schedule</label>
      <label>Sync interval (minutes)<input type="number" min={1} max={1440} required value={settings.intervalMinutes}
        onChange={event => change({ ...settings, intervalMinutes: Number(event.target.value) })} /></label>
    </fieldset>
    <p className="small muted">Both options are off by default. Metadata refresh covers existing links, including platforms not selected for import.
      Changed or missing files become conflicts: no automatic overwrites, renames, deletions, or verification.
      Disabling imports stops new transfers, but already-prepared imports remain in the library.
      Save settings before running sync; draft changes are not used by the worker.</p>
    <div className="row wrap">
      <button form="romm-connection" type="submit" disabled={locked}>Save sync settings</button>
      <button type="button" disabled={locked || !configured} onClick={() => setAction({ kind: 'sync' })}>Run saved sync / recheck conflicts</button>
      <button type="button" disabled={locked} onClick={() => { setError(''); void refresh().catch(error => setError(error instanceof Error ? error.message : String(error))) }}>Refresh conflicts</button>
    </div>
    {notice && <p role="status" className="notice success">{notice}</p>}
    {error && <p role="alert" className="notice error">{error}</p>}
    <h3>Synchronization conflicts</h3>
    {!loaded && !error && <p role="status">Loading synchronization conflicts...</p>}
    {loaded && !conflicts.length && <p className="muted">No synchronization conflicts recorded.</p>}
    <div className="integration-list">{conflicts.map(conflict => <article className="integration-item" key={conflict.rommId}>
      <div className="row spread"><strong>{conflict.name || `RomM #${conflict.rommId}`}</strong><Badge value={conflict.status} /></div>
      <p>{conflict.detail}</p><p className="small muted">RomM #{conflict.rommId} · {date(conflict.updated)}</p>
      {conflict.status === 'conflict' && <div className="row wrap">
        <button type="button" disabled={locked} onClick={() => setAction({ kind: 'keep-local', conflict })}>Keep local copy</button>
        <button type="button" disabled={locked} onClick={() => setAction({ kind: 'import', conflict })}>Import remote as separate copy</button>
      </div>}
    </article>)}</div>
    {action && <Modal title={action.kind === 'enable' ? 'Enable automatic inbound imports?' : action.kind === 'sync' ? 'Run saved synchronization?' : action.kind === 'keep-local' ? 'Keep local content?' : 'Import a separate remote version?'} close={() => !pending && setAction(undefined)}>
      {action.kind === 'enable' ? <p>New games from the selected platforms may download automatically and use local disk space. Files remain unchecked.
        No originals are overwritten or deleted. Save sync settings after confirming.</p> : action.kind === 'sync' ? <p>Use saved settings to discover/import new games, refresh linked metadata, and recheck conflicts.
        This may download ROMs if automatic imports are enabled. Ignored remote versions remain ignored.</p> : action.kind === 'keep-local' ? <p>Keep existing local files and metadata. Ignore the current remote file version until it changes again.
        No files are deleted. Rechecking does not reconsider an ignored remote version.</p> : <p>Download this remote version into a separate unchecked import.
        Existing files, verification results and audit history remain intact. Missing remote files cannot be imported.</p>}
      <div className="dialog-actions"><button disabled={pending} onClick={() => setAction(undefined)}>Cancel</button>
        <button className="primary" disabled={pending || action.kind === 'enable' && !settings.platformIds.length} onClick={confirm}>
          {action.kind === 'enable' ? 'Confirm inbound opt-in' : action.kind === 'sync' ? 'Confirm saved sync' : action.kind === 'keep-local' ? 'Confirm keep local' : 'Confirm separate import'}
        </button></div>
    </Modal>}
  </section>
}
