require('dotenv').config();

const express = require('express');
const axios = require('axios');
const cors = require('cors');
const helmet = require('helmet');
const morgan = require('morgan');

const app = express();

app.use(helmet());
app.use(cors());
app.use(express.json());
app.use(morgan('dev'));

const port = Number(process.env.PORT || 8787);
const usePrelive = String(process.env.QF_USE_PRELIVE || 'false') === 'true';
const clientId = (process.env.QF_CLIENT_ID || '').trim();
const clientSecret = (process.env.QF_CLIENT_SECRET || '').trim();

if (!clientId || !clientSecret) {
  throw new Error('Missing QF_CLIENT_ID or QF_CLIENT_SECRET');
}

const oauthBaseUrl = usePrelive
    ? 'https://prelive-oauth2.quran.foundation'
    : 'https://oauth2.quran.foundation';
const contentBaseUrl = usePrelive
    ? 'https://apis-prelive.quran.foundation/content/api/v4'
    : 'https://apis.quran.foundation/content/api/v4';
const searchBaseUrl = usePrelive
    ? 'https://apis-prelive.quran.foundation/search'
    : 'https://apis.quran.foundation/search';

let cachedToken = null;
let cachedTokenExpiresAt = 0;

function oauthHeaders() {
  return {
    'Content-Type': 'application/x-www-form-urlencoded',
    Accept: 'application/json',
  };
}

async function exchangeUserToken(params) {
  const response = await axios.post(
    `${oauthBaseUrl}/oauth2/token`,
    new URLSearchParams(params).toString(),
    {
      auth: {
        username: clientId,
        password: clientSecret,
      },
      headers: oauthHeaders(),
      timeout: 15000,
      validateStatus: (status) => status != null && status < 500,
    },
  );

  if (response.status >= 400 || !response.data || !response.data.access_token) {
    const error = new Error('Quran Foundation user token request failed');
    error.status = response.status;
    error.payload = response.data;
    throw error;
  }

  return {
    access_token: response.data.access_token,
    refresh_token: response.data.refresh_token,
    id_token: response.data.id_token,
    token_type: response.data.token_type,
    expires_in: response.data.expires_in,
    scope: response.data.scope,
  };
}

const qrBaseUrl = usePrelive
    ? 'https://apis-prelive.quran.foundation/quran-reflect/v1'
    : 'https://apis.quran.foundation/quran-reflect/v1';

let cachedPostToken = null;
let cachedPostTokenExpiresAt = 0;

async function getServiceToken() {
  const now = Date.now();
  if (cachedToken && now < cachedTokenExpiresAt) {
    return cachedToken;
  }

  const response = await axios.post(
    `${oauthBaseUrl}/oauth2/token`,
      new URLSearchParams({
        grant_type: 'client_credentials',
        scope: 'content',
      }).toString(),
    {
      auth: {
        username: clientId,
        password: clientSecret,
      },
      headers: oauthHeaders(),
      timeout: 15000,
      validateStatus: (status) => status != null && status < 500,
    },
  );

  if (response.status >= 400 || !response.data || !response.data.access_token) {
    const error = new Error('Quran Foundation token request failed');
    error.status = response.status;
    error.payload = response.data;
    throw error;
  }

  cachedToken = response.data.access_token;
  const expiresIn = Number(response.data.expires_in || 3600);
  cachedTokenExpiresAt = now + Math.max(expiresIn - 60, 60) * 1000;
  return cachedToken;
}

function filterQuery(query) {
  return Object.fromEntries(
    Object.entries(query).filter(([, value]) => value !== undefined && value !== null && value !== ''),
  );
}

async function qfGet(baseUrl, path, queryParameters) {
  const token = await getServiceToken();
  const response = await axios.get(`${baseUrl}${path}`, {
    params: filterQuery(queryParameters || {}),
    headers: {
      Accept: 'application/json',
      'x-client-id': clientId,
      'x-auth-token': token,
    },
    timeout: 20000,
    validateStatus: (status) => status != null && status < 500,
  });

  if (response.status >= 400) {
    const error = new Error('Quran Foundation request failed');
    error.status = response.status;
    error.payload = response.data;
    throw error;
  }

  return response.data;
}

function asyncRoute(handler) {
  return async (req, res) => {
    try {
      const data = await handler(req);
      res.json(data);
    } catch (error) {
      const status = error.status || 500;
      res.status(status).json({
        message: error.message,
        upstream: error.payload || null,
      });
    }
  };
}

app.get('/health', (_req, res) => {
  res.json({
    ok: true,
    prelive: usePrelive,
  });
});

app.post('/api/qf/auth/exchange', asyncRoute(async (req) => {
  const code = String(req.body?.code || '').trim();
  const codeVerifier = String(req.body?.codeVerifier || '').trim();
  const redirectUri = String(req.body?.redirectUri || '').trim();
  const scope = String(req.body?.scope || '').trim();

  if (!code || !codeVerifier || !redirectUri) {
    const error = new Error('Missing code, codeVerifier, or redirectUri');
    error.status = 400;
    throw error;
  }

  const params = {
    grant_type: 'authorization_code',
    code,
    redirect_uri: redirectUri,
    code_verifier: codeVerifier,
  };
  if (scope) {
    params.scope = scope;
  }

  return exchangeUserToken(params);
}));

app.post('/api/qf/auth/refresh', asyncRoute(async (req) => {
  const refreshToken = String(req.body?.refreshToken || '').trim();

  if (!refreshToken) {
    const error = new Error('Missing refreshToken');
    error.status = 400;
    throw error;
  }

  return exchangeUserToken({
    grant_type: 'refresh_token',
    refresh_token: refreshToken,
  });
}));

app.get('/api/qf/resources/tafsirs', asyncRoute((req) =>
  qfGet(contentBaseUrl, '/resources/tafsirs', req.query)));
app.get('/api/qf/resources/translations', asyncRoute((req) =>
  qfGet(contentBaseUrl, '/resources/translations', req.query)));
app.get('/api/qf/resources/recitations', asyncRoute((req) =>
  qfGet(contentBaseUrl, '/resources/recitations', req.query)));
app.get('/api/qf/chapters', asyncRoute((req) =>
  qfGet(contentBaseUrl, '/chapters', req.query)));
app.get('/api/qf/chapters/:chapterNumber/info', asyncRoute((req) =>
  qfGet(contentBaseUrl, `/chapters/${req.params.chapterNumber}/info`, req.query)));
app.get('/api/qf/verses/random', asyncRoute((req) =>
  qfGet(contentBaseUrl, '/verses/random', req.query)));
app.get('/api/qf/verses/by_key/:verseKey', asyncRoute((req) =>
  qfGet(contentBaseUrl, `/verses/by_key/${req.params.verseKey}`, req.query)));
app.get('/api/qf/verses/by_chapter/:chapterNumber', asyncRoute((req) =>
  qfGet(contentBaseUrl, `/verses/by_chapter/${req.params.chapterNumber}`, req.query)));
app.get('/api/qf/tafsirs/:resourceId/by_ayah/:verseKey', asyncRoute((req) =>
  qfGet(contentBaseUrl, `/tafsirs/${req.params.resourceId}/by_ayah/${req.params.verseKey}`, req.query)));
app.get('/api/qf/tafsirs/:resourceId/by_chapter/:chapterNumber', asyncRoute((req) =>
  qfGet(contentBaseUrl, `/tafsirs/${req.params.resourceId}/by_chapter/${req.params.chapterNumber}`, req.query)));
app.get('/api/qf/recitations/:recitationId/by_ayah/:verseKey', asyncRoute((req) =>
  qfGet(contentBaseUrl, `/recitations/${req.params.recitationId}/by_ayah/${req.params.verseKey}`, req.query)));
app.get('/api/qf/v1/search', asyncRoute((req) =>
  qfGet(searchBaseUrl, '/v1/search', req.query)));

// ── QuranReflect post feed (Content API – post.read scope) ───────────────

async function getPostToken() {
  const now = Date.now();
  if (cachedPostToken && now < cachedPostTokenExpiresAt) {
    return cachedPostToken;
  }

  const response = await axios.post(
    `${oauthBaseUrl}/oauth2/token`,
    new URLSearchParams({
      grant_type: 'client_credentials',
      scope: 'post.read',
    }).toString(),
    {
      auth: { username: clientId, password: clientSecret },
      headers: oauthHeaders(),
      timeout: 15000,
      validateStatus: (status) => status != null && status < 500,
    },
  );

  if (response.status >= 400 || !response.data || !response.data.access_token) {
    const error = new Error('post.read token request failed');
    error.status = response.status;
    error.payload = response.data;
    throw error;
  }

  cachedPostToken = response.data.access_token;
  const expiresIn = Number(response.data.expires_in || 3600);
  cachedPostTokenExpiresAt = now + Math.max(expiresIn - 60, 60) * 1000;
  return cachedPostToken;
}

async function qrGet(path, queryParameters) {
  const token = await getPostToken();
  const response = await axios.get(`${qrBaseUrl}${path}`, {
    params: filterQuery(queryParameters || {}),
    headers: {
      Accept: 'application/json',
      'x-client-id': clientId,
      'x-auth-token': token,
    },
    timeout: 20000,
    validateStatus: (status) => status != null && status < 500,
  });

  if (response.status >= 400) {
    const error = new Error('QuranReflect request failed');
    error.status = response.status;
    error.payload = response.data;
    throw error;
  }

  return response.data;
}

app.get('/api/qf/posts/feed', asyncRoute((req) =>
  qrGet('/posts/feed', req.query)));

app.get('/api/qf/posts/:postId', asyncRoute((req) =>
  qrGet(`/posts/${req.params.postId}`, req.query)));

app.listen(port, () => {
  console.log(`Noor AI Quran backend listening on http://localhost:${port}`);
});