package net.arena.stormfang.client;

import net.fabricmc.api.ClientModInitializer;
import com.mojang.blaze3d.platform.InputConstants;
import net.fabricmc.fabric.api.client.event.lifecycle.v1.ClientTickEvents;
import net.fabricmc.loader.api.FabricLoader;
import net.arena.stormfang.StormfangMod;

/**
 * Development-only automation used by CI to produce REAL in-game screenshots.
 *
 * Enabled only when: dev environment AND -Dstormfang.devtest=1 (set by `./gradlew runClient -Pdevtest`).
 * The CI presses F2 (xdotool) when it sees "SHOT_REQUESTED <n>" in the client log.
 * Every phase is wrapped in try/catch so a broken experiment can never crash the pipeline.
 *
 * Ticks only advance inside a world (menus/first-run dialogs are skipped), and phases
 * start slow enough for the tutorial toasts to fade out before the first photo.
 */
public class StormfangDevHarness implements ClientModInitializer {
	private int tick;
	private int menuTick;
	private boolean onboardingHandled;
	private boolean connectAttempted;
	private int connectTick = -1;

	@Override
	public void onInitializeClient() {
		boolean dev = FabricLoader.getInstance().isDevelopmentEnvironment();
		boolean enabled = dev && System.getProperty("stormfang.devtest") != null;
		if (!enabled) {
			return;
		}

		ClientTickEvents.END_CLIENT_TICK.register(client -> {
			if (client.level == null) {
				// first-run "accessibility" / title screens block quickPlay until dismissed:
				// close any such screen ourselves so the client proceeds into the world.
				menuTick++;
				if (onboardingHandled && !connectAttempted && menuTick >= connectTick) {
					connectAttempted = true;
					// mapping-agnostic: find the "launchMultiplayer/startMultiplayerPlay"-style
					// method on Minecraft(String host, int port) and invoke it.
					boolean ok = false;
					StringBuilder cands = new StringBuilder();
					for (java.lang.reflect.Method m : client.getClass().getDeclaredMethods()) {
						String mn = m.getName().toLowerCase();
						if (!(mn.contains("multiplayer") || mn.contains("connect"))) continue;
						Class<?>[] p = m.getParameterTypes();
						cands.append(m.getName()).append('(');
						for (Class<?> c : p) cands.append(c.getSimpleName()).append(',');
						cands.append(") ");
						if (p.length == 2 && p[0] == String.class
								&& (p[1] == int.class || p[1] == Integer.class)) {
							try {
								m.setAccessible(true);
								m.invoke(client, "localhost", 25565);
								StormfangMod.LOGGER.info("[Stormfang-DEV] connected via {}()", m.getName());
								ok = true;
								break;
							} catch (Throwable e) {
								StormfangMod.LOGGER.warn("[Stormfang-DEV] {} failed: {}", m.getName(), e.toString());
							}
						}
					}
					if (!ok) {
						StormfangMod.LOGGER.warn("[Stormfang-DEV] no launcher among: {}", cands);
					}
				}
				if (!onboardingHandled && menuTick > 30 && client.screen != null) {
					String cn = client.screen.getClass().getSimpleName();
					if (cn.contains("Accessibility")) {
						client.setScreen(null);
						onboardingHandled = true;
						connectTick = menuTick + 20;
						StormfangMod.LOGGER.info("[Stormfang-DEV] dismissed first-run screen {}", cn);
					}
				}

				return;
			}
			tick++;
			try {
				if (tick == 20) {
					// make sure nothing (pause menu etc.) covers the viewport
					if (client.screen != null) {
						client.setScreen(null);
					}
				}
				if (tick == 40) {
					StormfangMod.LOGGER.info("[Stormfang-DEV] joined world, giving stormblade");
					if (client.getConnection() != null) {
						client.getConnection().sendCommand("give @s stormfang:stormfang");
					}
				}
				if (tick == 300) {
					// ~26s after give: hotbar toast gone, sword in hand
					StormfangMod.LOGGER.info("[Stormfang-DEV] SHOT_REQUESTED 1");
				}
				if (tick == 350) {
					if (client.options.keyUse != null) {
						client.options.keyUse.click(InputConstants.getKey(1, 1)); // mouse right-click
						StormfangMod.LOGGER.info("[Stormfang-DEV] thunderclap triggered");
					}
				}
				if (tick == 375) {
					// lightning is alive ~1s, storm particles fresh
					StormfangMod.LOGGER.info("[Stormfang-DEV] SHOT_REQUESTED 2");
				}
				if (tick == 430) {
					if (client.options.keyInventory != null) {
						client.options.keyInventory.click(InputConstants.getKey(0, 69)); // keyboard E
					}
					StormfangMod.LOGGER.info("[Stormfang-DEV] inventory open, SHOT_REQUESTED 3");
				}
				if (tick == 500) {
					if (client.screen != null) {
						client.setScreen(null);
					}
					StormfangMod.LOGGER.info("[Stormfang-DEV] harness finished");
				}
			} catch (Throwable t) {
				StormfangMod.LOGGER.warn("[Stormfang-DEV] phase failed (non-fatal): {}", t.toString());
			}
		});
	}
}
