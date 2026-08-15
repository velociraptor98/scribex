/** 1b — Welcome: a title page, not a dashboard. */

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
          <div className="welcome-kicker">Offline · No account · No cloud</div>
          <h1 className="welcome-word">ScribeX</h1>
          <div className="welcome-rule" />
          <p className="welcome-lede">
            A quiet press for LaTeX. Type plain sentences; ScribeX sets the type,
            keeps the maths honest, and never asks for the network.
          </p>

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
            <p className="welcome-empty">
              Nothing yet. What you open here stays here — the list lives on this
              machine and goes no further.
            </p>
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
            <span>to search every document on this machine</span>
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
