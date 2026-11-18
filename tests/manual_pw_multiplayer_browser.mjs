// Serve a Pudge Wars browser build and start an isolated Polyworld relay.
// Optionally set PUDGEWARS_BROWSER_URL, PUDGEWARS_RELAY_URL, and PLAYWRIGHT_MODULE.
import assert from 'node:assert/strict';
import { createRequire } from 'node:module';

const require = createRequire(import.meta.url);
const { chromium } = require(process.env.PLAYWRIGHT_MODULE || 'playwright');
const bundleUrl = process.env.PUDGEWARS_BROWSER_URL || 'http://127.0.0.1:8719/';
const relayUrl = process.env.PUDGEWARS_RELAY_URL || 'ws://127.0.0.1:8092/ws';

const delay = (ms) => new Promise((resolve) => setTimeout(resolve, ms));
async function until(label, predicate, timeout = 25000) {
  const end = Date.now() + timeout;
  while (!predicate()) {
    if (Date.now() > end) throw new Error('Timed out: ' + label);
    await delay(100);
  }
}
const kinds = 'Hello Welcome ListRooms RoomList CreateRoom JoinRoom RoomState ConfigureRoom ClaimSeat ReleaseSeat Ready StartMatch BeginMatch SubmitCommand CommandAck TickPacket AppliedTick Catchup CaughtUp ReportHash MatchStatus LeaveRoom KickParticipant ReturnLobby FinishMatch Received Keepalive Failure AbortMatch PauseMatch ResizeRoom Prepared ReadyStatus PreparedDuration ServerNotice'.split(' ');
function decode(data) {
  const b = Buffer.isBuffer(data) ? data : Buffer.from(data);
  if (b.length < 64 || b.toString('ascii', 0, 4) !== 'PWRM') return {};
  let i = 64;
  const u = () => { const n = b.readUInt32LE(i); i += 4; return n; };
  const wide = () => { const n = b.readBigUInt64LE(i).toString(); i += 8; return n; };
  const bytes = () => { const n = u(); const s = b.subarray(i, i + n); i += n; return s; };
  const str = () => bytes().toString('utf8');
  const packet = { kind: kinds[b.readUInt32LE(8)], match: b.readUInt32LE(20) };
  const action = () => { const payload = bytes(); return payload.length < 4 ? -1 : payload.readUInt32LE(0); };
  if (packet.kind === 'Welcome') packet.participant = u();
  if (packet.kind === 'RoomState') {
    packet.room = str();
    packet.name = str();
    packet.owner = u();
    packet.revision = u();
    packet.phase = u();
    packet.rate = u();
    packet.flag = u();
    packet.config = str();
    packet.participants = Array.from({ length: u() }, () => ({
      id: u(), name: str(), connected: u(), ready: u()
    }));
    packet.seats = Array.from({ length: u() }, () => ({ owner: u(), name: str() }));
  }
  if (packet.kind === 'SubmitCommand') {
    packet.seat = u(); packet.sequence = wide(); packet.action = action();
  }
  if (packet.kind === 'TickPacket') {
    packet.tick = u();
    packet.commands = Array.from({ length: u() }, () => ({
      participant: u(), seat: u(), sequence: wide(), action: action()
    }));
  }
  if (packet.kind === 'ReportHash') { packet.tick = u(); packet.hash = wide(); }
  if (packet.kind === 'PauseMatch') packet.flag = u();
  if (packet.kind === 'MatchStatus') {
    packet.flag = u(); packet.phase = u(); packet.tick = u(); packet.detail = str();
  }
  if (packet.kind === 'Failure') packet.detail = str();
  return packet;
}
(async () => {
  const browser = await chromium.launch({
    channel: 'chrome', headless: true,
    args: ['--no-sandbox', '--enable-webgl', '--use-gl=angle', '--use-angle=swiftshader',
      '--enable-unsafe-swiftshader', '--disable-background-timer-throttling',
      '--disable-renderer-backgrounding', '--disable-backgrounding-occluded-windows']
  });
  const createPeer = async (name, room = '') => {
    const context = await browser.newContext({ viewport: { width: 1280, height: 800 } });
    const page = await context.newPage();
    const peer = { page, sent: [], received: [], reports: [], errors: [] };
    page.on('websocket', (socket) => {
      socket.on('framesent', (event) => peer.sent.push(decode(event.payload)));
      socket.on('framereceived', (event) => peer.received.push(decode(event.payload)));
    });
    peer.room = () => peer.received.filter((packet) => packet.kind === 'RoomState').at(-1);
    peer.click = async (x, y) => {
      await page.bringToFront();
      await page.mouse.move(x, y);
      await page.mouse.down();
      await delay(170);
      await page.mouse.up();
      await delay(250);
    };
    peer.key = async (key) => {
      await page.bringToFront();
      await page.keyboard.down(key);
      await delay(140);
      await page.keyboard.up(key);
      await delay(250);
    };
    page.on('console', (message) => {
      const text = message.text();
      if (text.startsWith('pw-state:')) peer.reports.push(JSON.parse(text.slice(9)));
      else if (message.type() === 'error' && !text.includes('404')) console.error(name, text);
    });
    page.on('pageerror', (error) => { peer.errors.push(error.message); console.error(name, error); });
    const url = new URL(bundleUrl);
    url.searchParams.set('server', relayUrl);
    url.searchParams.set('name', name);
    url.searchParams.set('mute', '1');
    if (room) url.searchParams.set('room', room);
    await page.goto(url.href, { waitUntil: 'load', timeout: 60000 });
    await page.waitForFunction(() => document.querySelector('#boot')?.classList.contains('gone'), null, { timeout: 60000 });
    await delay(700);
    return peer;
  };
  try {
    const west = await createPeer('Arena Input QA Host');
    await west.click(640, 518);
    await until('host WebSocket Welcome', () => west.received.some((packet) => packet.kind === 'Welcome'));
    await west.click(1043, 459);
    await until('host creates a room', () => west.room()?.room && west.room().seats[0]?.owner > 0);
    console.log('Room created', west.room().room);
    const east = await createPeer('Arena Input QA Guest', west.room().room);
    await until('guests joined same room', () => east.room()?.seats[1]?.owner > 0);
    await east.click(550, 221);
    await east.click(645, 292);
    await until('guest moved across the river',
      () => east.room()?.seats[3]?.owner > 0 &&
        east.room().seats[0].owner !== east.room().seats[3].owner);
    console.log('Guest moved to East');
    await until('both seats prove the lobby revision', () =>
      [west, east].every((peer) => peer.sent.some((packet) => packet.kind === 'PreparedDuration')));
    await west.click(1142, 754);
    await until('both clients render live network ticks',
      () => west.reports.at(-1)?.tick >= 12 && east.reports.at(-1)?.tick >= 12, 45000);
    console.log('Both arenas running', west.reports.at(-1).tick, east.reports.at(-1).tick);

    await west.key('r');
    await east.key('r');
    await until('both human owners submit R commands',
      () => [west, east].every((peer) => peer.sent.some((packet) =>
        packet.kind === 'SubmitCommand' && packet.action === 17)));
    const submissions = [west, east].map((peer) => peer.sent.find((packet) =>
      packet.kind === 'SubmitCommand' && packet.action === 17));
    assert.notEqual(submissions[0].seat, submissions[1].seat);
    await until('both clients receive the same two Rot commands',
      () => [west, east].every((peer) => submissions.every((input) =>
        peer.received.some((packet) => packet.commands?.some((command) =>
          command.seat === input.seat && command.sequence === input.sequence && command.action === 17)))));
    const lastInputTick = Math.max(...submissions.map((input) =>
      west.received.find((packet) => packet.commands?.some((command) =>
        command.seat === input.seat && command.sequence === input.sequence)).tick));
    await until('clients report equal authoritative hashes after input',
      () => west.sent.some((a) => a.kind === 'ReportHash' && a.tick >= lastInputTick &&
        east.sent.some((b) => b.kind === 'ReportHash' && b.tick === a.tick && b.hash === a.hash)));
    console.log('Authoritative human input reproduced and hashes agree');

    await west.key('Escape');
    await west.click(641, 311);
    await until('host sends pause and guest observes it', () =>
      west.sent.some((packet) => packet.kind === 'PauseMatch' && packet.flag === 1) &&
      east.received.some((packet) => packet.kind === 'MatchStatus' && packet.flag === 1));
    console.log('Pause propagated through relay');
    await west.click(641, 311);
    await until('host sends resume and guest observes it', () =>
      west.sent.some((packet) => packet.kind === 'PauseMatch' && packet.flag === 0) &&
      east.received.some((packet) => packet.kind === 'MatchStatus' && packet.flag === 0 && packet.phase === 1));
    console.log('Resume propagated through relay');
    await west.click(641, 466);
    await until('quit aborts active match for all peers', () =>
      west.sent.some((packet) => packet.kind === 'AbortMatch') &&
      east.received.some((packet) => packet.kind === 'MatchStatus' && packet.phase === 4));
    await until('host leaves the aborted match', () => west.sent.some((packet) => packet.kind === 'LeaveRoom'));
    assert.deepEqual(west.errors, []);
    assert.deepEqual(east.errors, []);
    console.log('Pause, resume, and quit propagated through relay');
  } finally {
    await browser.close();
  }
})().catch((error) => { console.error(error); process.exitCode = 1; });
