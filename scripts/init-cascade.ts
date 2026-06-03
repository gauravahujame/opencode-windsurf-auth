#!/usr/bin/env bun
/**
 * Calls InitializeCascadePanelState on the language server so it is ready
 * to handle chat requests without requiring the IDE to be open.
 *
 * Must be called after the language server port is reachable.
 *
 * Reads from environment:
 *   WINDSURF_API_KEY      - required
 *   WINDSURF_CSRF_TOKEN   - required
 *   WINDSURF_PORT         - gRPC port, default 42101
 *   WINDSURF_VERSION      - version string, default 1.9600.41
 */

import { execFileSync } from 'node:child_process';
import { writeFileSync, unlinkSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';

const apiKey = process.env.WINDSURF_API_KEY ?? '';
const csrfToken = process.env.WINDSURF_CSRF_TOKEN ?? '';
const port = parseInt(process.env.WINDSURF_PORT ?? '42101', 10);
const version = process.env.WINDSURF_VERSION ?? '1.9600.41';

if (!apiKey || !csrfToken) {
  process.stderr.write('init-cascade: WINDSURF_API_KEY and WINDSURF_CSRF_TOKEN must be set\n');
  process.exit(1);
}

// --- minimal protobuf helpers ---
function encodeVarint(value: number): number[] {
  const bytes: number[] = [];
  while (value > 127) {
    bytes.push((value & 0x7f) | 0x80);
    value >>>= 7;
  }
  bytes.push(value);
  return bytes;
}

function encodeStringField(fieldNumber: number, value: string): number[] {
  const tag = (fieldNumber << 3) | 2;
  const encoded = Array.from(new TextEncoder().encode(value));
  return [...encodeVarint(tag), ...encodeVarint(encoded.length), ...encoded];
}

function encodeMessageField(fieldNumber: number, nested: number[]): number[] {
  const tag = (fieldNumber << 3) | 2;
  return [...encodeVarint(tag), ...encodeVarint(nested.length), ...nested];
}

function encodeBoolField(fieldNumber: number, value: boolean): number[] {
  const tag = (fieldNumber << 3) | 0; // wire type 0 = varint
  return [...encodeVarint(tag), value ? 1 : 0];
}

// --- build Metadata message (field layout per WINDSURF_API_SPEC) ---
// Devin Desktop Metadata field numbers (discovered from extension.js):
//   ide_name=1, extension_version=2, api_key=3, locale=4, ide_version=7, session_id=10
const sessionId = crypto.randomUUID();
const metadata = [
  ...encodeStringField(1, 'windsurf'),
  ...encodeStringField(2, version),
  ...encodeStringField(3, apiKey),
  ...encodeStringField(4, 'en'),
  ...encodeStringField(7, version),
  ...encodeStringField(10, sessionId),
];

// InitializeCascadePanelStateRequest:
//   Field 1: metadata (Metadata message)
//   Field 3: workspace_trusted (bool = true)
const request = new Uint8Array([
  ...encodeMessageField(1, metadata),
  ...encodeBoolField(3, true),
]);

// gRPC-frame the request: 5-byte header (1 compressed flag + 4 length) + body
const header = new Uint8Array(5);
header[0] = 0; // not compressed
const view = new DataView(header.buffer);
view.setUint32(1, request.length, false); // big-endian
const framed = new Uint8Array(header.length + request.length);
framed.set(header, 0);
framed.set(request, 5);

const wrapperPath = join(process.cwd(), 'grpc-wrapper.mjs');
const grpcPath = '/exa.language_server_pb.LanguageServerService/InitializeCascadePanelState';

// Debug logging
process.stderr.write(`[init-cascade] Using version='${version}', apiKey len=${apiKey.length}, csrf len=${csrfToken.length}\n`);

let attempts = 0;
const maxAttempts = 5;
let lastError: unknown;

void (async () => {
  while (attempts < maxAttempts) {
    attempts++;

    // Write a fresh temp file for each attempt (grpc-wrapper deletes it after reading)
    const tmpFile = join(tmpdir(), `init_cascade_${Date.now()}_${attempts}.bin`);
    writeFileSync(tmpFile, framed);

    try {
      execFileSync(
        'node',
        [wrapperPath, String(port), csrfToken, grpcPath, tmpFile],
        { timeout: 10_000, stdio: ['pipe', 'pipe', 'pipe'] },
      );
      process.stdout.write(`[init-cascade] Cascade panel state initialized (attempt ${attempts})\n`);
      try { unlinkSync(tmpFile); } catch { /* ignore */ }
      process.exit(0);
    } catch (err) {
      lastError = err;
      process.stderr.write(`[init-cascade] Attempt ${attempts}/${maxAttempts} failed: ${String(err)}\n`);
      if (attempts < maxAttempts) {
        await new Promise(r => setTimeout(r, 2000));
      }
    }
  }

  process.stderr.write(`[init-cascade] All attempts failed: ${String(lastError)}\n`);
  process.exit(1);
})();
