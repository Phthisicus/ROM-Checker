import {
  History,
  RefreshCw,
  Shield,
  Trash2, Undo2
} from 'lucide-react'
import {
  bytes,
  date,
  type Cleanup,
  type Job, type Journal
} from '../../api'

import { Badge, Empty } from '../../components/Presentation'
import type { ConfirmAction, StartJob } from '../../workspace'

type Props = { journals: Journal[]; cleanup: Cleanup[]; cleanupJob?: Job; active?: Job; pending: boolean; start: StartJob; confirm: ConfirmAction }
export default function RecoveryView({ journals, cleanup, cleanupJob, active, pending, start, confirm }: Props) {
  return <>
          <div className="notice subtle"><Undo2 size={19} /><span>Undo the newest operation first. Changed files are preserved. Recovery may be partial if files were edited or removed.</span></div>
          <section className="panel"><div className="section-heading"><div><h2>Recovery journals</h2><p>Load the current journals from your mounted library.</p></div><button disabled={!!active || pending} onClick={() => start('history')}><RefreshCw size={16} />Refresh journals</button></div>
            {journals.length ? journals.map(j => <div className="journal-row" key={j.Name}><History size={20} /><div><strong>{j.Name}</strong><small>{j.Entries} journaled file(s) / {date(j.Modified)}</small></div><div className="row wrap"><button disabled={!!active || pending} onClick={() => start('undo-preview', { journal: j.Name })}>Preview undo</button><button disabled={!!active || pending} onClick={() => confirm({ title: 'Restore this operation?', message: 'Files will be restored where possible after hash checks. Unpacked copies may be removed only when their recovery evidence allows it. Undo the newest run first and read the preview log before proceeding.', action: 'undo', journal: j.Name })}><Undo2 size={16} />Restore</button></div></div>) : <Empty title="No journals loaded">Refresh journals to find previous moves and archive extractions, including CLI operations.</Empty>}</section>
          <section className="panel"><div className="section-heading"><div><h2>Processed archive cleanup</h2><p>Only recovery archives with complete extraction evidence are eligible.</p></div><button disabled={!!active || pending} onClick={() => start('cleanup-preview')}><Shield size={16} />Verify candidates</button></div>
            {cleanup.length > 0 ? <><div className="table-scroll"><table><thead><tr><th>Archive</th><th>Size</th><th>Eligibility</th><th>Evidence</th></tr></thead><tbody>{cleanup.map(item => <tr key={item.Path}><td className="mono">{item.Path}</td><td>{bytes(item.Bytes)}</td><td><Badge value={item.Eligible ? 'Verified' : 'Incomplete'} /></td><td>{item.Reason}</td></tr>)}</tbody></table></div><div className="panel-footer"><span>{bytes(cleanup.filter(c => c.Eligible).reduce((sum, c) => sum + c.Bytes, 0))} reclaimable</span><button className="danger-button" disabled={!!active || pending || !cleanup.some(c => c.Eligible)} onClick={() => confirm({ title: 'Permanently delete processed archives?', message: 'This is permanent deletion, not the recycle bin. Eligible recovery archives will be revalidated and deleted. Extraction undo becomes unavailable for deleted archives. Active ROM and arcade ZIPs are not cleanup candidates.', action: 'cleanup', sourceId: cleanupJob?.id, dangerous: true })}><Trash2 size={16} />Delete eligible archives</button></div></> : <Empty title="Verify before reclaiming space">Build a cleanup preview to identify processed archives whose extracted copies still match their hashes.</Empty>}</section>
        </>
}
