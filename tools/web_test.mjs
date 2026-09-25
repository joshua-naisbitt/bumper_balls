// End-to-end test of the Web export in Chromium, as a phone and as a desktop.
//
//   godot --headless --path . --export-debug Web build/web/index.html
//   (cd build/web && python3 -m http.server 8060) &
//   node tools/web_test.mjs OUT_DIR
//
// The phone run uses real browser touch events (CDP Input.dispatchTouchEvent),
// including two fingers at once, so it exercises the path a real phone takes:
// browser -> Godot's web input layer -> the game. Needs Playwright + Pillow.
import { execFileSync, execSync } from 'node:child_process';
import { createRequire } from 'node:module';

// Use a local Playwright if there is one, else the global install.
let chromium;
try {
  ({ chromium } = await import('playwright'));
} catch {
  const require = createRequire(import.meta.url);
  const globalRoot = execSync('npm root -g').toString().trim();
  ({ chromium } = require(require.resolve('playwright', { paths: [globalRoot] })));
}

const OUT = process.argv[2] || '.';
const PAGE = 'http://127.0.0.1:8060/index.html';
const HERE = new URL('.', import.meta.url).pathname;
const results = [];
const check = (ok, what) => { results.push(ok); console.log(`[web_test] ${ok ? 'PASS' : 'FAIL'}  ${what}`); };
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

// The UI is drawn inside WebGL, so buttons are found by colour in screenshots.
function findColor(file, rgb, tol, region) {
  const out = execFileSync('python3', [`${HERE}find_color.py`, file, rgb.join(','), String(tol), region.join(',')]).toString().trim();
  if (out === 'none') return null;
  const [x, y, n] = out.split(' ').map(Number);
  return { x, y, n };
}

async function boot(context, label) {
  const page = await context.newPage();
  const logs = [];
  const errors = [];
  page.on('console', (m) => logs.push(m.text()));
  page.on('pageerror', (e) => errors.push(String(e)));
  await page.goto(PAGE);
  const start = Date.now();
  while (!logs.some((l) => l.includes('[controls]')) && Date.now() - start < 120000) await sleep(250);
  const line = logs.find((l) => l.includes('[controls]')) || '';
  console.log(`[web_test] ${label}: ${line} (booted in ${((Date.now() - start) / 1000).toFixed(1)}s)`);
  await sleep(2500);
  return { page, logs, errors, line };
}

const browser = await chromium.launch({
  args: ['--use-angle=swiftshader', '--enable-unsafe-swiftshader', '--ignore-gpu-blocklist'],
});

// ---- phone -------------------------------------------------------------------
const PIXEL_7 = {
  viewport: { width: 915, height: 412 },
  isMobile: true,
  hasTouch: true,
  userAgent: 'Mozilla/5.0 (Linux; Android 14; Pixel 7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/129.0.0.0 Mobile Safari/537.36',
};
// Form-factor detection at the real device pixel ratio...
{
  const real = await browser.newContext({ ...PIXEL_7, deviceScaleFactor: 2.625 });
  const { line } = await boot(real, 'phone @2.625x');
  check(line.includes('form=PHONE') && line.includes('mode=TOUCH'), 'web on an Android phone -> PHONE form factor, TOUCH mode');
  await real.close();
}
// ...then play at 1x. Software WebGL at 2.6x manages a few frames a second, so
// game time falls far behind the wall clock and a ball can cross the whole
// dome between two screenshots. At 1x it runs close to real time. The CSS
// size is identical, so it is still a phone as far as the game can tell.
const phone = await browser.newContext({ ...PIXEL_7, deviceScaleFactor: 1 });
{
  const { page, errors, line } = await boot(phone, 'phone @1x');
  check(line.includes('form=PHONE'), 'still detected as a phone at 1x');
  const cdp = await phone.newCDPSession(page);
  const touch = (type, points) => cdp.send('Input.dispatchTouchEvent', {
    type, touchPoints: points.map(([x, y, id]) => ({ x, y, id })),
  });

  const dpr = 1;
  const W = 915 * dpr, H = 412 * dpr;
  const tapPx = (pt) => page.touchscreen.tap(pt.x / dpr, pt.y / dpr);
  const lobby = `${OUT}/phone-1-lobby.png`;
  await page.screenshot({ path: lobby });

  // An idle player among three CPUs gets shoved off in seconds, so first use
  // the cards to clear them: slot 2 to a (still) player, slots 3 and 4 empty.
  // Tapping a card's colour swatch lands on the card, which cycles it.
  const cards = [[76, 198, 255], [95, 224, 138], [255, 210, 76]]
    .map((rgb) => findColor(lobby, rgb, 18, [0.0, 0.2, 1.0, 0.62]));
  check(cards.every((c) => c !== null), 'all three CPU cards found on the phone lobby');
  if (cards.every((c) => c !== null)) {
    await tapPx(cards[0]); await sleep(300);                         // CPU -> Player
    for (const c of [cards[1], cards[2]]) {                          // CPU -> Player -> Empty
      await tapPx(c); await sleep(300); await tapPx(c); await sleep(300);
    }
  }
  await sleep(500);
  await page.screenshot({ path: `${OUT}/phone-1b-lobby-set.png` });
  const yellowLeft = findColor(`${OUT}/phone-1b-lobby-set.png`, [255, 210, 76], 18, [0.0, 0.2, 1.0, 0.62]);
  check(yellowLeft === null || yellowLeft.n < (cards[2]?.n ?? 0) * 0.6, 'tapping cards cycled slot 4 to empty (dimmed)');

  const btn = findColor(`${OUT}/phone-1b-lobby-set.png`, [255, 219, 122], 18, [0.3, 0.62, 0.7, 0.95]);
  check(btn !== null, 'START button found on the phone lobby');
  if (btn) await tapPx(btn);
  // Software WebGL at 2.6x DPR runs at a few frames a second and game time
  // lags the wall clock, so wait on what is on screen, not on a timer: poll
  // until the big white countdown digits have gone. Idle balls drift off the
  // dome by design, so the checks below have to happen promptly after GO.
  const play = `${OUT}/phone-2-play.png`;
  const t0 = Date.now();
  await sleep(2500);
  for (;;) {
    await page.screenshot({ path: play });
    const digits = findColor(play, [255, 255, 255], 12, [0.4, 0.2, 0.6, 0.5]);
    if (!digits || digits.n < 400 || Date.now() - t0 > 40000) break;
    await sleep(300);
  }
  const dash = findColor(play, [255, 91, 91], 40, [0.78, 0.55, 1.0, 1.0]);
  check(dash !== null, 'tapping START began a match with the on-screen DASH button showing');

  // Finger 1 on the stick with a gentle push; finger 2 taps DASH while
  // finger 1 stays down. One screenshot, with finger 1 still held, then shows
  // both: the knob parked under the drag (the stick is floating, so its base
  // lands under the finger -- at rest it sits well away from here) and the
  // dash cooldown ring, which only exists once the game has dashed.
  const sx = 150, sy = 300, pushX = 30;
  await touch('touchStart', [[sx, sy, 1]]);
  for (let i = 1; i <= 6; i++) { await touch('touchMove', [[sx + (pushX * i) / 6, sy, 1]]); await sleep(40); }
  // CDP takes the full set of fingers still touching, not a delta: a new id
  // in touchMove puts a finger down, and leaving one out lifts it. touchEnd
  // lifts everything. So finger 2 goes down and comes up again via touchMove,
  // with finger 1 listed throughout. The screenshot is taken straight after:
  // Pip's cooldown is only 0.85 s, and the ring is gone once it has run.
  await sleep(200);
  if (dash) {
    await touch('touchMove', [[sx + pushX, sy, 1], [dash.x / dpr, dash.y / dpr, 2]]);
    await sleep(120);
    await touch('touchMove', [[sx + pushX, sy, 1]]);
  }
  await sleep(100);
  const held = `${OUT}/phone-3-stick-and-dash.png`;
  await page.screenshot({ path: held });

  const kx = (sx + pushX) * dpr, ky = sy * dpr, win = 28;
  const knob = findColor(held, [201, 72, 72], 40,
    [(kx - win) / W, (ky - win) / H, (kx + win) / W, (ky + win) / H]);
  check(knob !== null && knob.n > 400,
    `real touch drag grabs the stick and moves its knob to the finger (${knob ? knob.n : 0} knob px at the drag point)`);

  if (dash) {
    // The ring starts at twelve o'clock just outside the button and sweeps
    // clockwise; sample the band above the top edge. At rest only the faint
    // outline (35% white) is there, which never reads as bright.
    const r = 78 * (412 / 533) * dpr;
    const band = [(dash.x - 12) / W, (dash.y - r - 12) / H, (dash.x + r) / W, (dash.y - r + 3) / H];
    const bright = (file) => findColor(file, [235, 235, 235], 35, band)?.n ?? 0;
    const before = bright(play);
    const after = bright(held);
    check(before < 10 && after > 25,
      `second finger dashes while the stick is held: cooldown ring appears (${before} -> ${after} bright px)`);
  }
  await touch('touchEnd', []);
  await sleep(300);

  // Pause button lives in the top-left corner.
  await page.touchscreen.tap(40, 40);
  await sleep(800);
  await page.screenshot({ path: `${OUT}/phone-5-pause.png` });
  const paused = findColor(`${OUT}/phone-5-pause.png`, [255, 219, 122], 18, [0.3, 0.1, 0.7, 0.45]);
  check(paused !== null, 'on-screen pause button opens the pause menu');

  // Held upright: a browser cannot lock orientation, so the game asks.
  await page.setViewportSize({ width: 412, height: 915 });
  await sleep(1500);
  await page.screenshot({ path: `${OUT}/phone-6-portrait.png` });
  const rotate = findColor(`${OUT}/phone-6-portrait.png`, [255, 219, 122], 18, [0.0, 0.3, 1.0, 0.7]);
  check(rotate !== null, 'portrait on a phone shows the turn-sideways prompt');
  check(errors.length === 0, `no page errors on phone (${errors.length})`);
  errors.forEach((e) => console.log('   ', e));
}
// One software-rendered WebGL game at a time is plenty for this machine.
await phone.close();

// ---- desktop -------------------------------------------------------------------
const desk = await browser.newContext({ viewport: { width: 1280, height: 720 } });
{
  const { page, errors, line } = await boot(desk, 'desktop');
  check(line.includes('form=DESKTOP') && line.includes('mode=KEYBOARD'), 'web on desktop -> DESKTOP form factor, KEYBOARD mode');
  await page.screenshot({ path: `${OUT}/desk-1-lobby.png` });
  await page.mouse.click(640, 360);  // focus the canvas like a player would
  await page.keyboard.press('Enter');
  await sleep(5500);
  await page.keyboard.press('Escape');
  await sleep(800);
  await page.screenshot({ path: `${OUT}/desk-2-pause.png` });
  const paused = findColor(`${OUT}/desk-2-pause.png`, [255, 219, 122], 18, [0.3, 0.1, 0.7, 0.45]);
  check(paused !== null, 'Enter starts and Esc pauses in a desktop browser');
  const noStick = findColor(`${OUT}/desk-2-pause.png`, [255, 91, 91], 40, [0.8, 0.6, 1.0, 1.0]);
  check(noStick === null, 'no touch controls on desktop');
  check(errors.length === 0, `no page errors on desktop (${errors.length})`);
}

await browser.close();
const failed = results.filter((r) => !r).length;
console.log(`[web_test] ${results.length - failed}/${results.length} passed`);
process.exit(failed ? 1 : 0);
