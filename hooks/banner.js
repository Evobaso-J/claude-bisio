#!/usr/bin/env node
// claude-bisio — SessionStart hook
// Prints ASCII banner directly to the user's terminal.
// Writes to /dev/tty (Unix) or the Windows console, NEVER to stdout,
// so Claude Code does not inject the banner as model context (zero tokens).

const fs = require('fs');
const path = require('path');

try {
  const bannerPath = path.join(__dirname, 'banner.txt');
  const banner = fs.readFileSync(bannerPath, 'utf8');

  if (process.platform === 'win32') {
    try {
      fs.writeFileSync('\\\\.\\CON', banner + '\n');
    } catch (_) {
      process.stderr.write(banner + '\n');
    }
  } else {
    try {
      fs.writeFileSync('/dev/tty', banner + '\n');
    } catch (_) {
      // Not a TTY (piped, CI, etc.) — skip silently.
    }
  }
} catch (_) {
  // Never block session start.
}

process.exit(0);
