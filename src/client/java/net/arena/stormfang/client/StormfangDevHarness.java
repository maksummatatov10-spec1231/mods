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
				if (!onboardingHandled && menuTick > 30 && client.screen != null) {
					String cn = client.screen.getClass().getSimpleName();
					if (cn.contains("Accessibility")) {
						client.setScreen(null);
						onboardingHandled = true;
						StormfangMod.LOGGER.info("[Stormfang-DEV] dismissed first-run screen {}", cn);
					}
				} else if (onboardingHandled && menuTick == 60 && client.level == null) {
					// quickPlay's one-shot task got consumed while the dialog was up —
					// so just do what it would have done: connect to the CI server.
					try {
						client.startMultiplayerPlay("localhost", 25565);
						StormfangMod.LOGGER.info("[Stormfang-DEV] startMultiplayerPlay called");
					} catch (Throwable e) {
						StormfangMod.LOGGER.warn("[Stormfang-DEV] connect failed: {}", e.toString());
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
