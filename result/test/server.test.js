// Unit tests for the result app, using Node's built-in test runner (no extra packages).
// Run with: npm test
//
// The options are set before server.js is loaded, because it builds the page at startup.
process.env.OPTION_A = 'Kampala';
process.env.OPTION_B = 'Entebbe <script>';

const test = require('node:test');
const assert = require('node:assert/strict');
const { server, escapeHtml, collectVotesFromResult } = require('../server.js');

let baseUrl;

test.before(async () => {
  // port 0 = let the OS pick a free port
  await new Promise((resolve) => server.listen(0, '127.0.0.1', resolve));
  baseUrl = `http://127.0.0.1:${server.address().port}`;
});

test.after(() => {
  server.close();
});

test('escapeHtml escapes characters that could inject HTML', () => {
  assert.equal(escapeHtml('<b>"Tom" & \'Jerry\'</b>'),
    '&lt;b&gt;&quot;Tom&quot; &amp; &#39;Jerry&#39;&lt;/b&gt;');
});

test('collectVotesFromResult counts both options', () => {
  const result = { rows: [{ vote: 'a', count: '7' }, { vote: 'b', count: '3' }] };
  assert.deepEqual(collectVotesFromResult(result), { a: 7, b: 3 });
});

test('collectVotesFromResult returns zero when there are no votes', () => {
  assert.deepEqual(collectVotesFromResult({ rows: [] }), { a: 0, b: 0 });
});

test('GET /healthz returns 200 ok', async () => {
  const res = await fetch(`${baseUrl}/healthz`);
  assert.equal(res.status, 200);
  assert.equal(await res.text(), 'ok');
});

test('GET / shows the configured vote options', async () => {
  const res = await fetch(`${baseUrl}/`);
  const html = await res.text();
  assert.equal(res.status, 200);
  assert.match(html, /Kampala/);
  assert.match(html, /Entebbe &lt;script&gt;/);
});

test('GET / never shows the raw template placeholders', async () => {
  const html = await (await fetch(`${baseUrl}/`)).text();
  assert.doesNotMatch(html, /__OPTION_[AB]__/);
});

test('static files are still served', async () => {
  const res = await fetch(`${baseUrl}/stylesheets/style.css`);
  assert.equal(res.status, 200);
});
