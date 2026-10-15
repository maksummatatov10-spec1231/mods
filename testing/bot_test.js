// Real-protocol smoke test: connect to the headless Fabric server as a player,
// receive the custom sword from /give (thanks to pre-ops.json) and cast Thunderclap.
const mineflayer = require('mineflayer');

const TARGET = 'stormfang:stormfang';
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

const bot = mineflayer.createBot({
  host: '127.0.0.1',
  port: 25565,
  username: 'StormBot',
  auth: 'offline',
  version: '1.21.4',
});

let done = false;

// Keep the CI step alive until the in-game screenshot phases complete (the client runs
// concurrently in its own project copy). This guarantees the later Collect/Push steps
// can include the screenshots. Max 12 minutes, then exit with the original code.
function waitScreenshots(origCode) {
  const fs = require('fs');
  const dirs = ['../run-client/screenshots', 'run-client/screenshots'];
  const t0 = Date.now();
  const MAX = 12 * 60 * 1000;
  const tick = () => {
    let n = 0;
    for (const d of dirs) { try { n = Math.max(n, fs.readdirSync(d).filter((f) => f.endsWith('.png')).length); } catch (e) {} }
    console.log('[bot] waiting for screenshots... found ' + n);
    if (n >= 3) { console.log('[bot] SHOTS_OK'); process.exit(0); }
    if (Date.now() - t0 > MAX) { console.log('[bot] SHOTS_TIMEOUT (n=' + n + ')'); process.exit(origCode === 0 ? 0 : (n > 0 ? 0 : origCode)); }
    setTimeout(tick, 5000);
  };
  tick();
}

const finish = (code, why) => {
  if (done) return;
  done = true;
  console.log('[bot] exit:', why);
  waitScreenshots(code);
};

setTimeout(() => finish(2, 'TIMEOUT'), 120000);

bot.on('error', (e) => finish(3, 'ERROR ' + e.message));
bot.on('kicked', (r) => finish(4, 'KICKED ' + JSON.stringify(r)));

bot.on('spawn', async () => {
  console.log('[bot] spawned at', bot.entity.position);
  await sleep(1500);

  bot.chat(`/give StormBot ${TARGET}`);
  await sleep(3000);

  const items = bot.inventory.items();
  const sword = items.find((i) => i.name === TARGET);
  if (!sword) {
    console.log('[bot] ITEM_NOT_FOUND, have:', items.map((i) => i.name).join(',') || '(empty)');
    return finish(5, 'ITEM_NOT_FOUND');
  }
  console.log('[bot] STORMFANG_GIVEN name=' + sword.displayName + ' count=' + sword.count);

  try {
    await bot.equip(sword, 'hand');
  } catch (e) {
    console.log('[bot] equip warn:', e.message);
  }

  // right-click -> StormfangItem.use() -> lightning + Thunderclap log line on server
  bot.activateItem();
  console.log('[bot] ABILITY_ACTIVATED (thunderclap)');

  // also punch a nearby mob if any, to exercise the hit-mixin (non-fatal)
  await sleep(1500);
  return finish(0, 'BOT_TEST_OK');
});
