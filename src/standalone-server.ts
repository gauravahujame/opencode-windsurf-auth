/**
 * Standalone Windsurf Proxy Server (Docker / External Access)
 *
 * Runs the OpenAI-compatible API proxy without requiring Windsurf to be
 * discovered on the same machine. Credentials are provided via environment
 * variables, and the server binds to 0.0.0.0 for external access.
 *
 * Required environment variables (standalone mode):
 *   WINDSURF_CSRF_TOKEN  - CSRF token from running Windsurf
 *   WINDSURF_API_KEY     - API key from Windsurf state
 *   WINDSURF_PORT        - gRPC port of Windsurf language server (default: 42100)
 *   WINDSURF_VERSION     - Windsurf version string (default: standalone)
 *
 * Optional environment variables:
 *   HOST                 - HTTP bind address (default: 0.0.0.0)
 *   PORT                 - HTTP port (default: 42100)
 *   API_KEY              - Bearer token to protect the HTTP API endpoints
 */

import {
  getStandaloneCredentials,
  getCredentials,
  isWindsurfRunning,
  getCanonicalModels,
  getModelVariants,
  type WindsurfCredentials,
} from '@windsurf/sdk';
import {
  createStreamingResponse,
  createNonStreamingResponse,
  handleToolPlanning,
  handleToolPlanningStream,
  openAIError,
  type ChatCompletionRequest,
} from './plugin.js';

// ============================================================================
// Configuration
// ============================================================================

const HOST = process.env.HOST || '0.0.0.0';
const PORT = parseInt(process.env.PORT || '42100', 10);
const PROXY_API_KEY = process.env.API_KEY || '';

function log(level: string, message: string) {
  const timestamp = new Date().toISOString();
  console.log(`[${timestamp}] [${level}] ${message}`);
}

// ============================================================================
// Credential Resolution
// ============================================================================

function resolveCredentials(): WindsurfCredentials {
  // Prefer standalone credentials when env vars are present
  const hasStandaloneEnv =
    process.env.WINDSURF_CSRF_TOKEN && process.env.WINDSURF_API_KEY;

  if (hasStandaloneEnv) {
    try {
      const creds = getStandaloneCredentials();
      log('INFO', 'Using standalone credentials from environment variables');
      return creds;
    } catch (err) {
      const msg = err instanceof Error ? err.message : String(err);
      log('WARN', `Standalone credential error: ${msg}`);
      // Fall through to auto-discovery
    }
  }

  // Fall back to auto-discovery (only works when Windsurf is running locally)
  if (isWindsurfRunning()) {
    try {
      const creds = getCredentials();
      log('INFO', 'Using auto-discovered credentials from running Windsurf');
      return creds;
    } catch (err) {
      const msg = err instanceof Error ? err.message : String(err);
      log('WARN', `Auto-discovery failed: ${msg}`);
    }
  }

  throw new Error(
    'No Windsurf credentials available. ' +
      'Set WINDSURF_CSRF_TOKEN and WINDSURF_API_KEY environment variables, ' +
      'or ensure Windsurf is running locally.'
  );
}

// ============================================================================
// Auth Middleware
// ============================================================================

function checkAuth(req: Request): Response | null {
  if (!PROXY_API_KEY) return null;

  const authHeader = req.headers.get('authorization') || '';
  const expected = `Bearer ${PROXY_API_KEY}`;

  if (authHeader !== expected) {
    return new Response(
      JSON.stringify({
        error: {
          message: 'Invalid or missing API key. Use Authorization: Bearer <token>',
          type: 'auth_error',
        },
      }),
      { status: 401, headers: { 'Content-Type': 'application/json' } }
    );
  }

  return null;
}

// ============================================================================
// Request Handler
// ============================================================================

const handler = async (req: Request): Promise<Response> => {
  try {
    const url = new URL(req.url);

    // Auth check
    const authError = checkAuth(req);
    if (authError) return authError;

    // Health check endpoint
    if (url.pathname === '/health') {
      const running = isWindsurfRunning();
      return new Response(
        JSON.stringify({
          ok: true,
          windsurf: running,
          mode: running ? 'auto-discovery' : 'standalone',
        }),
        { status: 200, headers: { 'Content-Type': 'application/json' } }
      );
    }

    // Models endpoint
    if (url.pathname === '/v1/models' || url.pathname === '/models') {
      const models = getCanonicalModels();
      return new Response(
        JSON.stringify({
          object: 'list',
          data: models.map((id: string) => {
            const variants = getModelVariants(id);
            return {
              id,
              object: 'model',
              created: Math.floor(Date.now() / 1000),
              owned_by: 'windsurf',
              ...(variants
                ? {
                    variants: Object.entries(variants).map(([name, meta]: [string, any]) => ({
                      id: name,
                      description: meta?.description ?? '',
                    })),
                  }
                : {}),
            };
          }),
        }),
        { status: 200, headers: { 'Content-Type': 'application/json' } }
      );
    }

    // Chat completions endpoint
    if (url.pathname === '/v1/chat/completions' || url.pathname === '/chat/completions') {
      let credentials: WindsurfCredentials;
      try {
        credentials = resolveCredentials();
      } catch (credErr) {
        const msg = credErr instanceof Error ? credErr.message : String(credErr);
        return openAIError(503, 'Windsurf credentials not available', msg);
      }

      try {
        const body = await req.json().catch(() => ({}));
        const requestBody = body as ChatCompletionRequest;
        const isStreaming = requestBody.stream === true;

        const hasToolsField =
          Array.isArray(requestBody.tools) && requestBody.tools.length > 0;
        const hasToolMessages = requestBody.messages?.some(
          (m) =>
            m.role === 'tool' ||
            (m.role === 'assistant' &&
              Array.isArray((m as any).tool_calls) &&
              (m as any).tool_calls.length > 0)
        );

        if (hasToolsField || hasToolMessages) {
          if (isStreaming) {
            const stream = handleToolPlanningStream(credentials, requestBody);
            return new Response(stream, {
              status: 200,
              headers: {
                'Content-Type': 'text/event-stream',
                'Cache-Control': 'no-cache',
                Connection: 'keep-alive',
              },
            });
          }
          return await handleToolPlanning(credentials, requestBody);
        }

        if (isStreaming) {
          const stream = createStreamingResponse(credentials, requestBody);
          return new Response(stream, {
            status: 200,
            headers: {
              'Content-Type': 'text/event-stream',
              'Cache-Control': 'no-cache',
              Connection: 'keep-alive',
            },
          });
        }

        const responseData = await createNonStreamingResponse(
          credentials,
          requestBody
        );
        return new Response(JSON.stringify(responseData), {
          status: 200,
          headers: { 'Content-Type': 'application/json' },
        });
      } catch (chatError) {
        const errMsg =
          chatError instanceof Error ? chatError.message : String(chatError);
        return openAIError(500, 'Chat completion failed', errMsg);
      }
    }

    return openAIError(404, `Unsupported path: ${url.pathname}`);
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    return openAIError(500, 'Proxy error', message);
  }
};

// ============================================================================
// Server Startup
// ============================================================================

async function main() {
  log('INFO', 'Starting Windsurf Standalone Proxy Server...');
  log('INFO', `Bind address: ${HOST}:${PORT}`);
  log('INFO', `API key protection: ${PROXY_API_KEY ? 'enabled' : 'disabled'}`);

  // Validate credentials at startup
  try {
    resolveCredentials();
    log('INFO', 'Credentials validated successfully');
  } catch (err) {
    const msg = err instanceof Error ? err.message : String(err);
    log('ERROR', `Credential validation failed: ${msg}`);
    process.exit(1);
  }

  const bunAny = globalThis as any;
  if (typeof bunAny.Bun === 'undefined' || typeof bunAny.Bun.serve !== 'function') {
    log('ERROR', 'Standalone server requires Bun runtime');
    process.exit(1);
  }

  try {
    const server = bunAny.Bun.serve({
      hostname: HOST,
      port: PORT,
      fetch: handler,
      idleTimeout: 100,
    });

    log('SUCCESS', `Server running at http://${HOST}:${server.port}`);
    log('INFO', `Health check: http://${HOST}:${server.port}/health`);
    log('INFO', 'Press Ctrl+C to stop');

    process.on('SIGINT', () => {
      log('INFO', 'Shutting down server...');
      process.exit(0);
    });

    process.on('SIGTERM', () => {
      log('INFO', 'Shutting down server...');
      process.exit(0);
    });
  } catch (error) {
    const msg = error instanceof Error ? error.message : String(error);
    log('ERROR', `Failed to start server: ${msg}`);
    process.exit(1);
  }
}

main();
