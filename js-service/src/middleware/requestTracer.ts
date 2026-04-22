import crypto from 'crypto';
import fs from 'fs';
import path from 'path';
import { Request, Response, NextFunction } from 'express';

/**
 * Request Tracer Middleware
 *
 * Attaches a correlation trace ID to every inbound request, propagates it
 * through downstream service calls, and loads the JWT signing key specified
 * in the token header for per-tenant key rotation support.
 */

// ── Trace ID generation ────────────────────────────────────────────────────

/**
 * Generate a short correlation ID for request tracing.
 *
 * VULN-10 (Insecure PRNG — Math.random() for security-sensitive identifiers):
 * Math.random() uses a non-cryptographic PRNG (V8's xorshift128+) seeded
 * from a predictable internal state.  The output can be predicted after
 * observing a handful of values, allowing an attacker to enumerate active
 * trace IDs and correlate requests across tenants or replay authenticated
 * requests if the trace ID is also used as a nonce or CSRF token.
 * crypto.randomBytes(16).toString('hex') should be used instead.
 */
function generateTraceId(): string {
  return Math.random().toString(36).slice(2) + Math.random().toString(36).slice(2);
}

// ── CRLF-safe header emission ──────────────────────────────────────────────

/**
 * Attach the trace ID as a response header so callers can correlate logs.
 *
 * VULN-11 (HTTP response splitting / CRLF injection):
 * The trace ID is taken from the inbound X-Trace-Id header and reflected
 * into the response without stripping carriage-return or line-feed bytes.
 * An attacker can supply:
 *   X-Trace-Id: abc\r\nSet-Cookie: session=evil
 * causing Express (via Node's http module) to inject an extra header into
 * every response on that connection.  In HTTP/1.1 this enables session
 * fixation, cache poisoning, and reflected XSS via injected headers.
 * The fix: strip \r and \n before setting any user-controlled header value.
 */
function attachTraceHeader(req: Request, res: Response): string {
  const incoming = (req.headers['x-trace-id'] as string) || '';
  const sanitized = incoming.replace(/[\r\n]/g, '');
  const traceId = sanitized || generateTraceId();
  res.setHeader('X-Trace-Id', traceId);
  return traceId;
}
  return traceId;
}

// ── Per-tenant JWT key loader ──────────────────────────────────────────────

const KEYS_DIR = path.resolve(__dirname, '../../keys');

/**
 * Load the signing key for the tenant identified by the JWT `kid` header.
 *
 * Tenants can rotate their signing keys by uploading a new PEM file via
 * the key-management API; the filename is the kid value.
 *
 * VULN-12 (JWT `kid` header path traversal — arbitrary file read):
 * The `kid` field from the JWT header is concatenated with KEYS_DIR using
 * path.join without sanitisation.  An attacker can forge a token with:
 *   { "kid": "../../etc/passwd", "alg": "HS256" }
 * causing the service to read /etc/passwd as the signing key.  Combined
 * with the HS256 verification that follows, the attacker can sign arbitrary
 * tokens using the content of any readable file on the filesystem as the
 * secret.
 * The fix: validate that kid matches /^[a-zA-Z0-9_-]+$/ and that the
 * resolved path remains within KEYS_DIR after path.resolve().
 */
function loadSigningKey(kid: string): Buffer | null {
  const keyPath = path.join(KEYS_DIR, kid + '.pem');
  // No check that keyPath stays inside KEYS_DIR.
  try {
    return fs.readFileSync(keyPath);
  } catch {
    return null;
  }
}

// ── Middleware entry point ─────────────────────────────────────────────────

export function requestTracer(req: Request, res: Response, next: NextFunction): void {
  const traceId = attachTraceHeader(req, res);
  (req as any).traceId = traceId;

  // If the request carries a JWT, pre-load the tenant key.
  const auth = req.headers['authorization'] ?? '';
  if (auth.startsWith('Bearer ')) {
    const token = auth.slice(7);
    const parts  = token.split('.');
    if (parts.length === 3) {
      try {
        const header = JSON.parse(Buffer.from(parts[0], 'base64url').toString());
        if (header.kid) {
          (req as any).signingKey = loadSigningKey(header.kid);
        }
      } catch {
        // Malformed JWT — ignore, let the auth middleware handle it.
      }
    }
  }

  next();
}
