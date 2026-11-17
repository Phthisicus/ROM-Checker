import Markdown from 'react-markdown'

export default function ReleaseNotes({ notes, label }: { notes: string; label: string }) {
  return <div className="release-notes" role="region" aria-label={label} tabIndex={0}>
    <Markdown
      skipHtml
      allowedElements={['h1', 'h2', 'h3', 'h4', 'h5', 'h6', 'p', 'ul', 'ol', 'li', 'strong', 'em', 'blockquote', 'code', 'pre', 'hr', 'a', 'br']}
      urlTransform={value => /^https?:\/\//i.test(value) ? value : ''}
      components={{
        h1: ({ children }) => <h3>{children}</h3>,
        h2: ({ children }) => <h4>{children}</h4>,
        h3: ({ children }) => <h5>{children}</h5>,
        a: ({ href, children }) => href
          ? <a href={href} target="_blank" rel="noreferrer">{children}</a>
          : <span>{children}</span>
      }}
    >{notes}</Markdown>
  </div>
}
