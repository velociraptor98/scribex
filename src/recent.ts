/** The recent-documents list on the welcome screen, kept in localStorage. */

export interface RecentDoc {
  path: string;
  /** \title{…} when the document declares one, else the file name. */
  title: string;
  sections: number;
  citations: number;
  /** Epoch ms of the last open or save. */
  opened: number;
}

const KEY = "scribex.recent";
const LIMIT = 8;

export function loadRecent(): RecentDoc[] {
  try {
    const raw = JSON.parse(localStorage.getItem(KEY) ?? "[]");
    if (!Array.isArray(raw)) return [];
    return raw
      .filter((d): d is RecentDoc => typeof d?.path === "string")
      .sort((a, b) => b.opened - a.opened)
      .slice(0, LIMIT);
  } catch {
    return [];
  }
}

export function remember(doc: Omit<RecentDoc, "opened">): RecentDoc[] {
  const next = [
    { ...doc, opened: Date.now() },
    ...loadRecent().filter((d) => d.path !== doc.path),
  ].slice(0, LIMIT);
  try {
    localStorage.setItem(KEY, JSON.stringify(next));
  } catch {
    // A full or disabled store costs us the list, not the document.
  }
  return next;
}

const TITLE_RE = /\\title\s*\{([^}]+)\}/;

export function documentTitle(source: string, path: string | null): string {
  const m = TITLE_RE.exec(source);
  if (m && m[1].trim()) return m[1].trim();
  return path?.split("/").pop() ?? "untitled.tex";
}

/** "2 min ago" · "Yesterday" · "3 Aug". */
export function when(ts: number, now = Date.now()): string {
  const mins = Math.floor((now - ts) / 60000);
  if (mins < 1) return "Just now";
  if (mins < 60) return `${mins} min ago`;
  const hours = Math.floor(mins / 60);
  if (hours < 24) return `${hours} hour${hours > 1 ? "s" : ""} ago`;
  const days = Math.floor(hours / 24);
  if (days === 1) return "Yesterday";
  const d = new Date(ts);
  const month = d.toLocaleString("en-GB", { month: "short" });
  return `${d.getDate()} ${month}`;
}
