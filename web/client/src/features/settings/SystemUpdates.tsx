import { useEffect, useState } from 'react'
import { api, url, type Info, type ReleaseInfo, type SystemDetails, type UpdateStatus } from '../../api'

function Notes({ release, title }: { release: ReleaseInfo; title: string }) {
  return <details><summary>{title}</summary>
    <pre className="release-notes">{release.notes}</pre>
    {release.releaseUrl && <a href={release.releaseUrl} target="_blank" rel="noreferrer">View source release</a>}
  </details>
}

export default function SystemUpdates({ info, fail, onUpdate, updateStatus }: {
  info?: Info; fail: (error: unknown) => void; onUpdate?: (status: UpdateStatus) => void; updateStatus?: UpdateStatus
}) {
  const [details, setDetails] = useState<SystemDetails>()
  const [status, setStatus] = useState<UpdateStatus>()
  const [checking, setChecking] = useState(false)
  const [loadError, setLoadError] = useState('')
  useEffect(() => { if (updateStatus) setStatus(updateStatus) }, [updateStatus])
  useEffect(() => {
    let active = true
    Promise.all([api<SystemDetails>('/system'), api<UpdateStatus>('/updates/status')])
      .then(([system, updates]) => { if (active) { setDetails(system); setStatus(updates) } })
      .catch(error => { if (active) { setLoadError('System information could not be loaded. Reopen Settings to retry.'); fail(error) } })
    return () => { active = false }
  }, [fail])
  async function checkUpdates() {
    setChecking(true)
    try {
      const updates = await api<UpdateStatus>('/updates/check', { method: 'POST' })
      setStatus(updates); onUpdate?.(updates)
    } catch (error) { fail(error) } finally { setChecking(false) }
  }
  const result = status?.result
  const timestamp = (value?: string) => value ? new Date(value).toLocaleString() : 'Not yet checked'
  return <section className="panel" id="system-updates" aria-labelledby="system-updates-heading">
    <h2 id="system-updates-heading">System & updates</h2>
    {loadError && <p role="alert">{loadError}</p>}
    <h3>Installed version</h3>
    <dl className="server-info">
      <div><dt>Application version</dt><dd>{info?.version ?? 'Loading...'}</dd></div>
      <div><dt>Channel</dt><dd>{info?.channel ?? 'Local'}</dd></div>
      <div><dt>Build / attempt</dt><dd>{info?.buildNumber ?? 'Local'} / {info?.buildAttempt ?? '-'}</dd></div>
    </dl>
    <details><summary>Detailed version information</summary><dl className="server-info">
      <div><dt>Built (UTC)</dt><dd>{info?.builtUtc ?? 'Local source build'}</dd></div>
      <div><dt>Source revision</dt><dd className="mono">{info?.commit}</dd></div>
      <div><dt>Metadata format</dt><dd>{info?.metadataFormatVersion ?? 'Unavailable'}</dd></div>
      <div><dt>Database schema</dt><dd>{info?.schema ? `${info.schema.version} (supported ${info.schema.minimumSupported}-${info.schema.maximumSupported})` : 'Unavailable'}</dd></div>
    </dl>
      {info?.workflowUrl && <a href={info.workflowUrl} target="_blank" rel="noreferrer">Build workflow</a>}
    </details>
    {details && <Notes release={details.release} title="Installed release notes" />}
    <h3>Updates</h3>
    <p className="small">Checks follow this image's channel only. Nothing is installed automatically. Switch channels by explicitly deploying a different channel image.</p>
    <p className="small muted">{details?.updates.enabled
      ? details.updates.scheduled ? 'Automatic checks run about every six hours. Manual checks are limited to once per minute.' : 'Manual checks enabled. Scheduled checks are disabled.'
      : 'Update checks are opt-in. Set ROMCHECKER_CHECK_UPDATES=true on the server. Add ROMCHECKER_SCHEDULED_UPDATES=true for scheduled checks.'}</p>
    <button type="button" disabled={checking || status?.status === 'checking'} onClick={checkUpdates}>{checking || status?.status === 'checking' ? 'Checking...' : 'Check for updates'}</button>
    {status && <div role="status" className={`notice ${status.status === 'error' || result?.schemaCompatible === false ? 'error' : status.status === 'available' ? 'success' : 'subtle'}`}>
      <span>{status.message}{result?.version && ` Version ${result.version} · Build ${result.buildNumber}`}
        {status.stale && ' Last successful result shown below is stale.'}</span>
    </div>}
    <dl className="server-info">
      <div><dt>Last attempt</dt><dd>{timestamp(status?.lastAttemptUtc)}</dd></div>
      <div><dt>Last successful check</dt><dd>{timestamp(status?.lastSuccessUtc)}</dd></div>
    </dl>
    {result?.notesError && <p role="alert">{result.notesError}</p>}
    {result?.release && <>
      <Notes release={result.release} title={`Available release notes (${result.version})${status?.stale ? ' - stale result' : ''}`} />
      {result.release.upgradeNotes.length > 0 && <div><h4>Upgrade requirements</h4>{result.release.upgradeNotes.map(text => <p key={text}>{text}</p>)}</div>}
      {result.release.limitations.length > 0 && <div><h4>Known limitations</h4>{result.release.limitations.map(text => <p key={text}>{text}</p>)}</div>}
    </>}
    <p className="small">Back up application data, ROM storage and configuration before upgrading. Matching database schemas do not guarantee safe upgrades or rollback; review the release notes. Older images may require a matching database backup.</p>
    <p className="small">To upgrade manually, pull your configured image and recreate the services through Docker Compose or your deployment manager. A restart alone does not update a container. Keep application, storage and signature-updater versions aligned.</p>
    <h3>System information</h3>
    {details && <details><summary>Runtime & storage details</summary>
      <p className="small muted">These describe the {details.system.scope.toLowerCase()}, not the Docker host. Paths are deployment paths visible to the application.</p>
      <dl className="server-info">
        <div><dt>Operating system</dt><dd>{details.system.operatingSystem}</dd></div>
        <div><dt>Architecture</dt><dd>{details.system.architecture}</dd></div>
        <div><dt>Runtime</dt><dd>{details.system.runtime}</dd></div>
        <div><dt>Process started</dt><dd>{timestamp(details.system.startedUtc)}</dd></div>
        <div><dt>Uptime when loaded</dt><dd>{Math.floor(details.system.uptimeSeconds / 3600)}h {Math.floor(details.system.uptimeSeconds % 3600 / 60)}m</dd></div>
        <div><dt>Antivirus</dt><dd>{info?.antivirus}</dd></div>
        <div><dt>Library path</dt><dd className="mono">{details.paths.library}</dd></div>
        <div><dt>Data path</dt><dd className="mono">{details.paths.data}</dd></div>
        <div><dt>Engine path</dt><dd className="mono">{details.paths.engine}</dd></div>
        <div><dt>Proxy base path</dt><dd>{details.paths.pathBase || '/'}</dd></div>
      </dl>
    </details>}
    <a href={url('/diagnostics/build')} download>Download build diagnostics</a>
    <p className="small muted">Diagnostics include build, schema and runtime information only; credentials, environment variables and storage paths are excluded.</p>
  </section>
}
