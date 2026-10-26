import { ArrowRight, Gamepad2, LoaderCircle, Shield, Undo2 } from 'lucide-react'
import { useState, type FormEvent } from 'react'
import { api } from '../../api'

export default function Login({ onLogin }: { onLogin: () => void }) {
  const [password, setPassword] = useState('')
  const [error, setError] = useState('')
  const [pending, setPending] = useState(false)
  async function submit(event: FormEvent) {
    event.preventDefault(); setPending(true); setError('')
    try { await api('/login', { method: 'POST', body: JSON.stringify({ password }) }); setPassword(''); onLogin() }
    catch (err) { setError((err as Error).message) }
    finally { setPending(false) }
  }
  return <main className="login-shell"><div className="login-art"><div className="logo-mark"><Gamepad2 size={40} /></div>
    <span className="eyebrow">A BETTER HOME FOR YOUR COLLECTION</span><h1>Your collection.<br /><em>Understood.</em></h1>
    <p>Verify every file. Keep what matters.<br />Bring order to your ROM library.</p>
    <div className="login-features"><span><Shield size={18} /> Evidence-led verification</span><span><Undo2 size={18} /> Recoverable file operations</span></div>
    </div><form className="login-form" onSubmit={submit}><span className="eyebrow">ROM CHECKER</span><h2>Welcome back</h2>
      <p className="muted">Sign in to manage your self-hosted library.</p>
      <label>Administrator password<input type="password" autoComplete="current-password" required autoFocus value={password} onChange={e => setPassword(e.target.value)} /></label>
      {error && <div className="notice error" role="alert">{error}</div>}
      <button className="primary" disabled={pending}>{pending ? <LoaderCircle className="spin" size={18} /> : <ArrowRight size={18} />}Sign in</button>
      <p className="small muted">Use the password configured on your server. ROM files stay on your own storage.</p>
    </form></main>
}
