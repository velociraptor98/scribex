/** The 40px bar across the top of every screen.
 *
 *  The mockup draws macOS traffic lights; the window is configured with an
 *  overlay title bar so those are the real ones, drawn by the system. All this
 *  needs to do is leave room for them and stay draggable. */

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
