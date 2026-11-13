import { Link2 } from 'lucide-react'
import { useEffect, useState } from 'react'
import { api } from '../../api'
import { Badge } from '../../components/Presentation'
import { openIntegration } from '../../navigation'
import RommView from './RommView'
import './romm.css'

const integrations = [{
  id: 'romm', name: 'RomM',
  description: 'Publish verified copies, import remote games, and synchronize linked metadata.',
  statusPath: '/romm/config',
  Settings: RommView,
}]

type Props = { integration?: string; advanced?: boolean; fail: (error: unknown) => void }

function IntegrationCard({ integration }: { integration: typeof integrations[number] }) {
  const [configured, setConfigured] = useState<boolean>()
  const [error, setError] = useState('')
  async function load() {
    setError('')
    try { setConfigured((await api<{ configured: boolean }>(integration.statusPath)).configured) }
    catch (error) { setError(error instanceof Error ? error.message : String(error)) }
  }
  useEffect(() => { void load() }, [integration])
  return <article className="panel connection-card">
    <div className="row spread wrap"><h2><Link2 size={20} aria-hidden="true" />{integration.name}</h2>
      {error ? <Badge value="Status unavailable" /> : configured === undefined
        ? <span role="status" className="small muted">Loading status...</span>
        : <Badge value={configured ? 'Configured' : 'Not configured'} />}
    </div>
    <p>{integration.description}</p>
    {error && <div role="alert" className="notice error"><span>{error}</span><button type="button" onClick={load}>Retry status</button></div>}
    <a className="button" href={`#/settings/connections/${integration.id}`}
      onClick={event => {
        if (event.button !== 0 || event.metaKey || event.ctrlKey || event.shiftKey || event.altKey) return
        event.preventDefault(); openIntegration(integration.id)
      }}>Open {integration.name} settings</a>
  </article>
}

export default function ConnectionsView({ integration, advanced, fail }: Props) {
  if (integration !== undefined) {
    const selected = integrations.find(item => item.id === integration)
    return selected ? <selected.Settings advanced={advanced} fail={fail} />
      : <section className="panel"><h2>Integration not found</h2><p>Select an available integration using Connections in the top breadcrumb. No settings have been changed.</p></section>
  }
  return <div className="connections-grid">{integrations.map(item => <IntegrationCard key={item.id} integration={item} />)}</div>
}
