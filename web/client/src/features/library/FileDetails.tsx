import {
  ArrowUpRight,
  ShieldAlert
} from 'lucide-react';
import {
  bytes,
  preview,
  type Job,
  type Result
} from '../../api';

import { Badge, Modal } from '../../components/Presentation';

type Props = { file: Result; selected?: Job; close: () => void; review: (decision: string) => void }
export default function FileDetails({ file, selected, close, review }: Props) {
  return <Modal title={file.FileName} close={close}><div className="row wrap"><Badge value={file.Category} /><span className="muted">{file.Console} / {bytes(file.Length)}</span></div><p>{file.Reason}</p>
      <div className="file-evidence">{(['Authenticity', 'IntegrityStatus', 'AntivirusStatus', 'MalwareStatus', 'Security', 'DatStrength', 'Header', 'Sources', 'Libraries', 'CheckedUtc', 'AntivirusCheckedUtc'] as const).map(key => <div key={key}><span>{key.replace(/([a-z])([A-Z])/g, '$1 $2')}</span><strong>{file[key] || 'Not available'}</strong></div>)}</div>
      {file.Threats && <div className="notice error">{file.Threats}</div>}{file.Notes && <p className="small">{file.Notes}</p>}
      <dl className="file-paths">{(['FullName', 'Target', 'SHA256', 'SHA1', 'MD5', 'CRC32', 'DupOf'] as const).filter(key => file[key]).map(key => <div key={key}><dt>{key}</dt><dd className="mono">{file[key]}</dd></div>)}</dl>
      {file.SHA256 && <a href={`https://www.virustotal.com/gui/file/${encodeURIComponent(file.SHA256)}`} target="_blank" rel="noreferrer" className="text-button">View hash on VirusTotal <ArrowUpRight size={15} /></a>}
      <div className="dialog-actions wrap"><button disabled={!selected || !preview(selected) || !file.Reviewable} onClick={() => review('keep')}>Keep in place</button><button disabled={!selected || !preview(selected) || !file.Reviewable || file.Security !== 'Clean'} onClick={() => review('original')}>Mark original</button><button disabled={!selected || !preview(selected) || !file.Reviewable} onClick={() => review('quarantine')}><ShieldAlert size={16} />Quarantine</button></div><p className="small muted">Review decisions affect a new preview, not files on disk. Security warnings cannot be overridden here. Disc sets and companions remain grouped.</p>
    </Modal>
}
