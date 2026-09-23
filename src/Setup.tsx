/** The first-run download of the LaTeX essentials.
 *
 *  Tectonic ships engines, not packages or fonts, so a new install cannot set
 *  anything until those have been fetched once (see docs/OFFLINE.md). This is
 *  where the reader is asked for that download and watches it happen: a card on
 *  the title page, a banner above the editor. */

export type CacheState = "unknown" | "cold" | "downloading" | "failed" | "ready";

export interface SetupProgress {
  /** Resources downloaded so far in this run. */
  files: number;
  /** The one arriving now. */
  current?: string;
  error?: string;
}

/** Measured against an empty cache: the warmup set plus the four plates. The
 *  bundle can drift, so this only paces the bar and is quoted as "about". */
export const SETUP_FILES = 440;
const SETUP_MB = 45;

interface Props {
  state: CacheState;
  progress: SetupProgress;
  onStart: () => void;
  /** One line above the editor, rather than the title-page card. */
  compact?: boolean;
}

export default function Setup({ state, progress, onStart, compact }: Props) {
  if (state === "unknown" || state === "ready") return null;

  // Never shows as finished: the last few files can outnumber the estimate,
  // and a full bar that is still working reads as a hang.
  const share = Math.min(progress.files / SETUP_FILES, 0.97);

  const headline =
    state === "downloading" ? "Downloading the LaTeX essentials"
    : state === "failed" ? "The download stopped"
    : "One-time setup";

  const body =
    state === "downloading" ? (
      <>
        {progress.current ? <code>{progress.current}</code> : "Connecting…"}
        <span className="setup-count tnum">
          {progress.files} of about {SETUP_FILES} files
        </span>
      </>
    ) : state === "failed" ? (
      <>
        {progress.error ?? "Something went wrong."} Check your connection and try
        again — {progress.files > 0 ? "what already arrived is kept." : "nothing is lost."}
      </>
    ) : compact ? (
      <>Nothing can be built until the LaTeX packages and fonts are downloaded — about {SETUP_MB} MB, once.</>
    ) : (
      <>
        ScribeX typesets without the internet, but first it needs the core LaTeX
        packages and fonts: about {SETUP_MB} MB, a minute or two, once. Documents
        open as soon as it finishes, and every plate works offline after that.
      </>
    );

  const action = state !== "downloading" && (
    <button className={`btn btn-primary${compact ? " btn-sm" : ""}`} onClick={onStart}>
      {state === "failed" ? "Try again" : "Download now"}
    </button>
  );

  const bar = state === "downloading" && (
    <div className="setup-bar" role="progressbar" aria-valuenow={Math.round(share * 100)}
      aria-valuemin={0} aria-valuemax={100}>
      <div className="setup-bar-fill" style={{ width: `${share * 100}%` }} />
    </div>
  );

  if (compact) {
    return (
      <div className={`banner setup-banner${state === "failed" ? " is-failed" : ""}`}>
        <span className="setup-banner-head">{headline}</span>
        <span className="setup-banner-body">{body}</span>
        {bar}
        {action}
        {state === "downloading" && (
          <span className="banner-note">keep writing — the preview appears when it finishes</span>
        )}
      </div>
    );
  }

  return (
    <section className={`setup${state === "failed" ? " is-failed" : ""}`}>
      <div className="rubric">{headline}</div>
      <p className="setup-body">{body}</p>
      {bar}
      {action}
      {state === "downloading" && (
        <p className="setup-note">Documents open as soon as this finishes.</p>
      )}
    </section>
  );
}
