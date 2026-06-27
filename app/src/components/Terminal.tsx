import { useEffect, useRef } from "react";
import { Terminal } from "@xterm/xterm";
import { FitAddon } from "@xterm/addon-fit";
import "@xterm/xterm/css/xterm.css";
import { listen } from "@tauri-apps/api/event";
import {
  killPty,
  resizePty,
  spawnPty,
  writePty,
  type PtyOutput,
} from "../lib/catalog";

interface Props {
  wslName: string;
  command: string;
  active: boolean;
  onExit: (code: number) => void;
}

export function TerminalView({ wslName, command, active, onExit }: Props) {
  const containerRef = useRef<HTMLDivElement>(null);
  const sessionRef = useRef<number | null>(null);

  useEffect(() => {
    if (!active || !containerRef.current || !command) return;

    const term = new Terminal({
      cursorBlink: true,
      fontFamily: "Consolas, monospace",
      fontSize: 13,
      theme: { background: "#0a0e14" },
    });
    const fitAddon = new FitAddon();
    term.loadAddon(fitAddon);
    term.open(containerRef.current);
    fitAddon.fit();

    let unlisten: (() => void) | undefined;
    let sessionId = 0;

    const setup = async () => {
      sessionId = await spawnPty(wslName, command);
      sessionRef.current = sessionId;

      const un = await listen<PtyOutput>(`pty-output-${sessionId}`, (event) => {
        const payload = event.payload;
        if (payload.kind === "stdout" || payload.kind === "stderr") {
          term.write(payload.data);
        }
        if (payload.kind === "exit") {
          onExit(parseInt(payload.data, 10) || 0);
        }
      });
      unlisten = un;

      term.onData((data) => {
        writePty(sessionId, data).catch(console.error);
      });

      const ro = new ResizeObserver(() => {
        fitAddon.fit();
        resizePty(sessionId, term.cols, term.rows).catch(console.error);
      });
      ro.observe(containerRef.current!);

      return () => ro.disconnect();
    };

    let cleanupResize: (() => void) | undefined;
    setup()
      .then((fn) => {
        cleanupResize = fn;
      })
      .catch((err) => {
        term.writeln(`Erreur PTY : ${err}`);
      });

    return () => {
      unlisten?.();
      cleanupResize?.();
      if (sessionRef.current !== null) {
        killPty(sessionRef.current).catch(console.error);
      }
      term.dispose();
    };
  }, [active, wslName, command, onExit]);

  return <div ref={containerRef} className="terminal-container" />;
}
