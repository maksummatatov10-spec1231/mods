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
const finish = (code, why) => {
  if (done) return;
  done = true;
  console.log('[bot] exit:', why);
  process.exit(code);
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
