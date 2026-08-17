// Cognito Hosted UI login via Authorization Code + PKCE — the flow the
// SPA app client is configured for (terraform/modules/cognito: no client
// secret, allowed_oauth_flows = ["code"]). No OAuth library dependency;
// PKCE is ~30 lines with the Web Crypto API, and hand-rolling it here is
// a deliberate choice for a portfolio project — it demonstrates
// understanding the flow rather than just importing one.
//
// Tokens live in sessionStorage rather than localStorage: they're cleared
// when the tab closes instead of persisting indefinitely, a reasonable
// default for a demo storefront with no "remember me" requirement.

const DOMAIN = import.meta.env.VITE_COGNITO_DOMAIN;
const CLIENT_ID = import.meta.env.VITE_COGNITO_CLIENT_ID;
const REDIRECT_URI = import.meta.env.VITE_COGNITO_REDIRECT_URI;

const VERIFIER_KEY = 'pkce_code_verifier';
const TOKENS_KEY = 'auth_tokens';

function base64UrlEncode(bytes) {
  let str = '';
  for (const b of new Uint8Array(bytes)) str += String.fromCharCode(b);
  return btoa(str).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
}

function generateCodeVerifier() {
  const bytes = new Uint8Array(32);
  crypto.getRandomValues(bytes);
  return base64UrlEncode(bytes.buffer);
}

async function generateCodeChallenge(verifier) {
  const digest = await crypto.subtle.digest('SHA-256', new TextEncoder().encode(verifier));
  return base64UrlEncode(digest);
}

export async function redirectToLogin() {
  const verifier = generateCodeVerifier();
  sessionStorage.setItem(VERIFIER_KEY, verifier);
  const challenge = await generateCodeChallenge(verifier);

  const params = new URLSearchParams({
    response_type: 'code',
    client_id: CLIENT_ID,
    redirect_uri: REDIRECT_URI,
    scope: 'openid email profile',
    code_challenge_method: 'S256',
    code_challenge: challenge,
  });

  window.location.href = `https://${DOMAIN}/oauth2/authorize?${params.toString()}`;
}

export function logout() {
  sessionStorage.removeItem(TOKENS_KEY);
  const params = new URLSearchParams({
    client_id: CLIENT_ID,
    logout_uri: REDIRECT_URI,
  });
  window.location.href = `https://${DOMAIN}/logout?${params.toString()}`;
}

// Call once on app load. If the URL has ?code=... (we've just been
// redirected back from the Hosted UI), exchange it for tokens and strip
// the query string so a page refresh doesn't try to reuse a spent code.
export async function handleAuthCallback() {
  const url = new URL(window.location.href);
  const code = url.searchParams.get('code');
  if (!code) return;

  const verifier = sessionStorage.getItem(VERIFIER_KEY);
  if (!verifier) return; // stray ?code= with no matching verifier — ignore

  const body = new URLSearchParams({
    grant_type: 'authorization_code',
    client_id: CLIENT_ID,
    code,
    redirect_uri: REDIRECT_URI,
    code_verifier: verifier,
  });

  const res = await fetch(`https://${DOMAIN}/oauth2/token`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: body.toString(),
  });

  if (!res.ok) {
    console.error('Token exchange failed', await res.text());
    return;
  }

  const tokens = await res.json();
  sessionStorage.setItem(TOKENS_KEY, JSON.stringify(tokens));
  sessionStorage.removeItem(VERIFIER_KEY);

  // Drop ?code=&state= from the address bar now that it's been used.
  url.searchParams.delete('code');
  url.searchParams.delete('state');
  window.history.replaceState({}, '', url.pathname + url.search);
}

export function getIdToken() {
  const raw = sessionStorage.getItem(TOKENS_KEY);
  if (!raw) return null;
  try {
    return JSON.parse(raw).id_token || null;
  } catch {
    return null;
  }
}

export function isAuthenticated() {
  return Boolean(getIdToken());
}

// Decodes the ID token's payload client-side (no signature check — the
// token was already validated by API Gateway's JWT authorizer on every
// authenticated request; this is purely to read `sub`/`email` for
// display and to tag orders with a userId).
export function getCurrentUser() {
  const token = getIdToken();
  if (!token) return null;
  try {
    const payload = JSON.parse(atob(token.split('.')[1].replace(/-/g, '+').replace(/_/g, '/')));
    return { sub: payload.sub, email: payload.email };
  } catch {
    return null;
  }
}
