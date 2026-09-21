import { PLATES, Plate } from "./templates";
import { RecentDoc, when } from "./recent";
import TitleBar from "./TitleBar";

interface Props {
  recent: RecentDoc[];
  onNew: () => void;
  onOpen: () => void;
  onOpenRecent: (doc: RecentDoc) => void;
  onPlate: (plate: Plate) => void;
  onSearch: () => void;
}

export default function Welcome({
  recent, onNew, onOpen, onOpenRecent, onPlate, onSearch,
}: Props) {
  return (
    <div className="screen">
      <TitleBar />
      <div className="welcome">
        <section className="welcome-title">
          <div className="welcome-lockup">
            <svg className="welcome-mark" viewBox="0 0 100 100" aria-hidden>
              <g fill="none" stroke="var(--accent)" strokeWidth="6.5" strokeLinecap="round">
                <path d="M23 33 C23 23 34 24 35 33 C37 47 63 53 65 67 C66 77 77 76 77 67" />
                <path d="M77 33 C77 23 66 24 65 33 C63 47 37 53 35 67 C34 77 23 76 23 67" />
              </g>
            </svg>
            <h1 className="welcome-word">Scribe<span className="welcome-x">X</span></h1>
          </div>
          <div className="welcome-rule" />

          <div className="welcome-actions">
            <button className="btn btn-primary" onClick={onNew}>New document</button>
            <button className="btn" onClick={onOpen}>Open…</button>
          </div>

          <div className="welcome-plates">
            <div className="hairline" />
            <div className="welcome-plates-row">
              <span>Start from a plate —</span>
              {PLATES.map((p, i) => (
                <span key={p.name}>
                  <button className="linkish" onClick={() => onPlate(p)} title={p.note}>
                    {p.name}
                  </button>
                  {i < PLATES.length - 1 && <span className="sep"> · </span>}
                </span>
              ))}
            </div>
          </div>
        </section>

        <div className="welcome-divider" />

        <section className="welcome-recent">
          <div className="rubric">Recently set</div>

          {recent.length === 0 ? (
            <p className="welcome-empty">No recent documents.</p>
          ) : (
            <div className="recent-list">
              {recent.map((d) => (
                <button key={d.path} className="recent" onClick={() => onOpenRecent(d)}>
                  <span className="recent-plate" aria-hidden />
                  <span className="recent-main">
                    <span className="recent-title">{d.title}</span>
                    <span className="recent-path">
                      {shorten(d.path)}
                      {d.sections > 0 && ` · ${d.sections} section${d.sections > 1 ? "s" : ""}`}
                      {d.citations > 0 && ` · ${d.citations} citation${d.citations > 1 ? "s" : ""}`}
                    </span>
                  </span>
                  <span className="recent-when tnum">{when(d.opened)}</span>
                </button>
              ))}
            </div>
          )}

          <div className="welcome-search">
            <button className="key" onClick={onSearch}>⌘K</button>
            <span>to search documents</span>
          </div>
        </section>
      </div>
    </div>
  );
}

/** Show the last two path segments — enough to tell two ch3.tex files apart. */
function shorten(path: string): string {
  return path.split("/").slice(-2).join("/");
}
