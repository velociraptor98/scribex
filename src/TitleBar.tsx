/** The 40px bar across the top of every screen.
 *
 *  The window uses an overlay title bar, so the traffic lights are drawn by the
 *  system; this only leaves room for them and stays draggable. */

interface Props {
  /** Centred, in small caps. Omitted on the welcome screen. */
  title?: string;
  /** Right-hand indicator: the offline lamp, or a build state. */
  right?: React.ReactNode;
}

export default function TitleBar({ title, right }: Props) {
  return (
    <header className="titlebar" data-tauri-drag-region>
      <div className="titlebar-lights" />
      {title && <div className="titlebar-name">{title}</div>}
      <div className="titlebar-right">{right}</div>
    </header>
  );
}
