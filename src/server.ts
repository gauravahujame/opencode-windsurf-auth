/**
 * Standalone Windsurf Proxy Server
 * 
 * This file starts the Windsurf proxy server as a standalone process.
 * It's used by the install.sh script to run the server in the background.
 * 
 * Usage:
 *   bun run dist/server.js
 */

import { ensureWindsurfProxyServer } from './plugin.js';
import { isWindsurfRunning } from './plugin/auth.js';

async function main() {
  console.log('[INFO] Starting Windsurf Proxy Server...');

  if (!isWindsurfRunning()) {
    console.error('[ERROR] Windsurf is not running. Please launch Windsurf first.');
    process.exit(1);
  }

  try {
    const baseURL = await ensureWindsurfProxyServer();
    console.log('[SUCCESS] Windsurf Proxy Server started successfully');
    console.log(`[INFO] Proxy URL: ${baseURL}`);
    console.log('[INFO] Press Ctrl+C to stop the server');

    // Keep the process running
    process.on('SIGINT', () => {
      console.log('[INFO] Shutting down server...');
      process.exit(0);
    });

    process.on('SIGTERM', () => {
      console.log('[INFO] Shutting down server...');
      process.exit(0);
    });

  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    console.error('[ERROR] Failed to start server:', message);
    process.exit(1);
  }
}

main();
