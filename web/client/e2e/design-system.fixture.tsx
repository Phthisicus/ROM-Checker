import { createRoot } from 'react-dom/client'
import { useState } from 'react'
import { Button, IconButton, Notice, Select, StatusBadge, Table, TextInput, Tooltip, type Tone } from '../src/design-system/components'
import { Dialog } from '../src/design-system/Dialog'
import '../src/features/library/catalog.css'
import '../src/features/storage/collections.css'
import '../src/style.css'
import '../src/redesign.css'
import '../src/design-system/tokens.css'
import '../src/design-system/foundation.css'

// Browser-only component fixture, never imported by the application.
function Fixture() {
  const [dialog, setDialog] = useState<'dialog' | 'drawer'>()
  return <main className="redesigned" style={{ padding: 16 }}>
    <h1>Design system fixture</h1>
    <div className="row wrap">
      <Button size="sm">Small</Button><Button>Default</Button><Button size="lg">Large</Button>
      <IconButton size="sm" label="Small icon"><svg width="16" height="16" aria-hidden="true" /></IconButton>
      <IconButton label="Default icon"><svg width="16" height="16" aria-hidden="true" /></IconButton>
      <IconButton size="lg" label="Large icon"><svg width="16" height="16" aria-hidden="true" /></IconButton>
      <Button variant="primary">Primary</Button><Button variant="danger">Destructive</Button>
      <Tooltip content="Checks preserve originals."><button type="button">Check information</button></Tooltip>
      <Button onClick={() => setDialog('dialog')}>Open dialog</Button>
      <Button onClick={() => setDialog('drawer')}>Open drawer</Button>
    </div>
    <TextInput label="ROM directory" hint="Use a real library mount." />
    <Select label="Platform"><option>NES</option></Select>
    <div className="row wrap">{(['neutral', 'info', 'success', 'warning', 'danger'] as Tone[]).map(tone => <StatusBadge key={tone} tone={tone}>{tone}</StatusBadge>)}</div>
    <Notice tone="danger">Connection failed. Retry when RomM is available.</Notice>
    <Table caption="ROM files"><thead><tr><th scope="col">Path</th><th scope="col">Integrity</th></tr></thead><tbody><tr><td className="mono">{'LongDirectory/'.repeat(20)}Game.nes</td><td>Unchecked</td></tr></tbody></Table>
    {dialog && <Dialog title="Review ROM evidence" variant={dialog} onClose={() => setDialog(undefined)}><TextInput label="Review note" /><Button onClick={() => setDialog(undefined)}>Done</Button></Dialog>}
  </main>
}

createRoot(document.getElementById('root')!).render(<Fixture />)
