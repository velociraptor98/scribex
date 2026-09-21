// Runs before every `npm run tauri …`. On macOS, stages the bundled libraries
// and writes tauri.macos.conf.json, which Tauri reads before it starts.
import { execFileSync } from "node:child_process";
import { fileURLToPath } from "node:url";

if (process.platform === "darwin") {
  const script = fileURLToPath(new URL("./stage-dylibs.sh", import.meta.url));
  execFileSync("sh", [script], { stdio: "inherit" });
}
