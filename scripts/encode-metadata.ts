#!/usr/bin/env bun
/**
 * Outputs a protobuf-encoded Metadata message to stdout.
 * Used to pass credentials to the language server via --stdin_initial_metadata.
 *
 * Reads from environment:
 *   WINDSURF_API_KEY  - required
 *   WINDSURF_VERSION  - optional, defaults to 1.9600.41
 */

const apiKey = process.env.WINDSURF_API_KEY ?? '';
const version = process.env.WINDSURF_VERSION ?? '1.9600.41';
const sessionId = crypto.randomUUID();

if (!apiKey) {
  process.stderr.write('encode-metadata: WINDSURF_API_KEY is not set\n');
  process.exit(1);
}

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
  const tag = (fieldNumber << 3) | 2; // wire type 2 = length-delimited
  const encoded = Array.from(new TextEncoder().encode(value));
  return [...encodeVarint(tag), ...encodeVarint(encoded.length), ...encoded];
}

// Devin Desktop Metadata field numbers (discovered from extension.js):
//   ide_name=1, extension_version=2, api_key=3, locale=4, ide_version=7, session_id=10
const metadata = new Uint8Array([
  ...encodeStringField(1, 'windsurf'),
  ...encodeStringField(2, version),
  ...encodeStringField(3, apiKey),
  ...encodeStringField(4, 'en'),
  ...encodeStringField(7, version),
  ...encodeStringField(10, sessionId),
]);

process.stdout.write(metadata);
