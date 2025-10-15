const express = require('express');
const session = require('express-session');
const axios = require('axios');
const crypto = require('crypto');
require('dotenv').config();

const port = Number(process.env.PORT || 3000);
const authentikUrl = String(process.env.AUTHENTIK_URL || '').replace(/\/$/, '');
const clientId = process.env.CLIENT_ID || '';
const clientSecret = process.env.CLIENT_SECRET || '';
const configuredPublicBase = (process.env.PUBLIC_BASE_URL || '').replace(/\/$/, '');

if (!/^https?:\/\//.test(authentikUrl)) {
  throw new Error('Set AUTHENTIK_URL (e.g., http://host:9000 or https://host)');
}
if (!clientId || !clientSecret) {
  throw new Error('Set CLIENT_ID and CLIENT_SECRET from Authentik → Application.');
}

const app = express();
app.disable('x-powered-by');

app.set('trust proxy', true);

function getOrigin(req) {
  if (configuredPublicBase) return configuredPublicBase;
  const proto = (req.headers['x-forwarded-proto'] || req.protocol || 'http').split(',')[0].trim();
  const host = req.headers['x-forwarded-host'] || req.headers.host;
  if (!host) throw new Error('Cannot detect host; set PUBLIC_BASE_URL.');
  return `${proto}://${host}`;
}

app.use(session({
  secret: process.env.SESSION_SECRET || 'change_me_session_secret',
  resave: false,
  saveUninitialized: false,
  cookie: {
    httpOnly: true,
    sameSite: 'lax',
    secure: false
  }
}));

app.get('/', (req, res) => {
  res.send(`<!doctype html>
<html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>Authentik OAuth2 Test Application</title>
<style>
body{font-family:system-ui,-apple-system,Segoe UI,Roboto,Ubuntu,Arial,sans-serif;background:#f8fafc;margin:0}
.wrap{max-width:900px;margin:64px auto;padding:0 16px}
h1{font-size:40px;margin:0 0 16px}
.card{background:#fff;border:1px solid #e5e7eb;border-radius:12px;padding:24px}
.btn{display:inline-block;background:#16a34a;color:#fff;text-decoration:none;padding:12px 18px;border-radius:8px;font-weight:600;margin-top:16px}
code{background:#f1f5f9;border:1px solid #e5e7eb;border-radius:6px;padding:2px 6px}
</style></head>
<body><div class="wrap">
  <h1>Authentik OAuth2 Test Application</h1>
  <div class="card">
    <p>This application tests OAuth2 authentication with your Authentik instance.</p>
    <p><b>Authentik:</b> <code>${authentikUrl}</code></p>
    <p><b>Client ID:</b> <code>${clientId}</code></p>
    <a class="btn" href="/login">🔒 Login with Authentik</a>
  </div>
</div></body></html>`);
});

app.get('/login', (req, res) => {
  const origin = getOrigin(req);
  const redirectUri = `${origin}/auth/callback`;

  if (req.session?.cookie) req.session.cookie.secure = origin.startsWith('https://');

  const state = crypto.randomBytes(16).toString('hex');
  req.session.oauthState = state;

  const url = new URL(`${authentikUrl}/application/o/authorize/`);
  url.searchParams.set('client_id', clientId);
  url.searchParams.set('redirect_uri', redirectUri);
  url.searchParams.set('response_type', 'code');
  url.searchParams.set('scope', 'openid profile email');
  url.searchParams.set('state', state);

  console.log('Authorize URL:', url.toString());
  res.redirect(url.toString());
});

app.get('/auth/callback', async (req, res) => {
  const origin = getOrigin(req);
  const redirectUri = `${origin}/auth/callback`;
  const { code, state } = req.query;

  if (!code || !state || state !== req.session.oauthState) {
    return res.status(400).send('Invalid OAuth state or code');
  }

  try {
    const tokenResp = await axios.post(
      `${authentikUrl}/application/o/token/`,
      new URLSearchParams({
        grant_type: 'authorization_code',
        code: String(code),
        redirect_uri: redirectUri,
        client_id: clientId,
        client_secret: clientSecret
      }),
      { headers: { 'Content-Type': 'application/x-www-form-urlencoded' } }
    );

    req.session.tokens = tokenResp.data;

    try {
      const { data } = await axios.get(`${authentikUrl}/application/o/userinfo/`, {
        headers: { Authorization: `Bearer ${tokenResp.data.access_token}` }
      });
      req.session.userinfo = data;
    } catch {
      req.session.userinfo = null;
    }

    res.redirect('/protected');
  } catch (e) {
    console.error('Token exchange failed:', e.response?.data || e.message);
    res.status(500).send('Token exchange failed');
  }
});

app.get('/protected', (req, res) => {
  if (!req.session?.tokens?.access_token) return res.redirect('/');
  res.type('json').send(JSON.stringify({
    message: 'Authenticated',
    userinfo: req.session.userinfo || null
  }, null, 2));
});

app.listen(port, '0.0.0.0', () => {
  console.log(`✅ App listening on port ${port}`);
  console.log(`🔗 AUTHENTIK_URL: ${authentikUrl}`);
  console.log(`🌐 PUBLIC_BASE_URL: ${configuredPublicBase || '(auto-detect)'}`);
});
