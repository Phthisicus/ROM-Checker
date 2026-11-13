import { useCallback, useEffect, useState } from 'react'
import { api, date } from '../../api'
import { Badge, Modal } from '../../components/Presentation'
import RommChecklist from './RommChecklist'

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
  return <>
    <div className="integration-grid romm-section">
    <section className="panel">
      <span className="eyebrow">ROMM TO ROM CHECKER</span>
      <h2>Import from RomM</h2>
      <p>Import new games only from explicitly selected platforms. Incoming files start unchecked.</p>
      <label className="catalog-check romm-automation"><input type="checkbox" disabled={locked} checked={settings.autoImport}
        onChange={event => event.target.checked ? setAction({ kind: 'enable' }) : change({ ...settings, autoImport: false })} />
        Automatically import new RomM games from selected platforms</label>
      <RommChecklist title="Platforms allowed for automatic import" disabled={locked}
        choices={choices.map(id => ({ id: String(id),
          name: `${platforms.filter(platform => platform.platformId === id).map(platform => platform.console).join(', ') || 'Unavailable mapping'} (RomM platform ${id})` }))}
        selected={settings.platformIds.map(String)} change={ids => change({ ...settings, platformIds: ids.map(Number) })}
        empty="Add and save platform mappings before enabling inbound imports." />
      <p className="small muted">No platforms selected means no automatic imports. Exact whole-game hashes prevent duplicate imports and import/export loops.</p>
      {settings.autoImport && !settings.platformIds.length && <p role="alert" className="notice error">Select at least one platform or turn off automatic imports before saving.</p>}
    </section>
    <section className="panel">
      <span className="eyebrow">LINKED GAMES & TIMING</span>
      <h2>Metadata & schedule</h2>
      <label className="catalog-check romm-automation"><input type="checkbox" disabled={locked} checked={settings.refreshMetadata}
        onChange={event => change({ ...settings, refreshMetadata: event.target.checked })} />
        Refresh linked metadata and detect conflicts on a schedule</label>
      <p className="small muted">Metadata refresh covers all existing links, including platforms not selected for import.
        Descriptive metadata never approves or verifies ROMs.</p>
      <label>Sync interval (minutes)<input form="romm-connection" name="syncInterval" disabled={locked} type="number" min={1} max={1440} required value={settings.intervalMinutes}
        onChange={event => change({ ...settings, intervalMinutes: Number(event.target.value) })} /></label>
      <p className="small muted">Shared by automatic imports and scheduled metadata refresh: 1-1440 minutes.
        Both automations are off by default. Save RomM settings to apply changes.</p>
      <button type="button" disabled={locked || !configured} onClick={() => setAction({ kind: 'sync' })}>Run saved synchronization</button>
      <p className="small muted">Runs saved settings and rechecks conflicts, not your unsaved changes. May download games when saved automatic imports are enabled.</p>
      <details><summary>Synchronization safeguards</summary><p className="small muted">Changed or missing files become conflicts.
        No automatic overwrites, renames, deletions, or verification. Disabling imports stops new transfers;
        already-prepared imports remain in the library.</p></details>
    </section>
    </div>
    <section className="panel romm-section">
    <div className="row spread wrap">
      <h2>Synchronization conflicts</h2>
      <button type="button" disabled={locked} onClick={() => { setError(''); void refresh().catch(error => setError(error instanceof Error ? error.message : String(error))) }}>Refresh conflicts</button>
    </div>
    {notice && <p role="status" className="notice success">{notice}</p>}
    {error && <p role="alert" className="notice error">{error}</p>}
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
        No originals are overwritten or deleted. Save RomM settings after confirming.</p> : action.kind === 'sync' ? <p>Use saved settings to discover/import new games, refresh linked metadata, and recheck conflicts.
        This may download ROMs if automatic imports are enabled. Ignored remote versions remain ignored.</p> : action.kind === 'keep-local' ? <p>Keep existing local files and metadata. Ignore the current remote file version until it changes again.
        No files are deleted. Rechecking does not reconsider an ignored remote version.</p> : <p>Download this remote version into a separate unchecked import.
        Existing files, verification results and audit history remain intact. Missing remote files cannot be imported.</p>}
      <div className="dialog-actions"><button disabled={pending} onClick={() => setAction(undefined)}>Cancel</button>
        <button className="primary" disabled={pending || action.kind === 'enable' && !settings.platformIds.length} onClick={confirm}>
          {action.kind === 'enable' ? 'Confirm inbound opt-in' : action.kind === 'sync' ? 'Confirm saved sync' : action.kind === 'keep-local' ? 'Confirm keep local' : 'Confirm separate import'}
        </button></div>
    </Modal>}
    </section>
  </>
}
