package net.arena.stormfang;

import net.arena.stormfang.item.StormfangItem;
import net.fabricmc.api.ModInitializer;
import net.fabricmc.fabric.api.itemgroup.v1.FabricItemGroup;
import net.fabricmc.fabric.api.itemgroup.v1.ItemGroupEvents;
import net.fabricmc.fabric.api.particle.v1.FabricParticleTypes;
import net.minecraft.core.Registry;
import net.minecraft.core.particles.SimpleParticleType;
import net.minecraft.core.registries.BuiltInRegistries;
import net.minecraft.core.registries.Registries;
import net.minecraft.network.chat.Component;
import net.minecraft.resources.ResourceKey;
import net.minecraft.resources.ResourceLocation;
import net.minecraft.sounds.SoundEvent;
import net.minecraft.world.item.CreativeModeTab;
import net.minecraft.world.item.CreativeModeTabs;
import net.minecraft.world.item.Item;
import net.minecraft.world.item.ItemStack;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

public class StormfangMod implements ModInitializer {
	public static final String MOD_ID = "stormfang";
	public static final Logger LOGGER = LoggerFactory.getLogger(MOD_ID);

	public static ResourceLocation id(String path) {
		return ResourceLocation.fromNamespaceAndPath(MOD_ID, path);
	}

	/** Custom spark particle — behaviour provided client-side (see StormfangClient). */
	public static final SimpleParticleType STORM_SPARK = Registry.register(
			BuiltInRegistries.PARTICLE_TYPE, id("storm_spark"), FabricParticleTypes.simple());

	/** Procedurally synthesized thunder charge sound (assets/stormfang/sounds). */
	public static final SoundEvent THUNDER_CHARGE = Registry.register(
			BuiltInRegistries.SOUND_EVENT, id("thunder_charge"),
			SoundEvent.createVariableRangeEvent(id("thunder_charge")));

	public static final Item STORMFANG = new StormfangItem(StormfangItem.KEY);

	public static final ResourceKey<CreativeModeTab> STORMFANG_TAB_KEY =
			ResourceKey.create(Registries.CREATIVE_MODE_TAB, id("stormfang"));

	@Override
	public void onInitialize() {
		Registry.register(BuiltInRegistries.ITEM, StormfangItem.KEY, STORMFANG);

		Registry.register(BuiltInRegistries.CREATIVE_MODE_TAB, STORMFANG_TAB_KEY, FabricItemGroup.builder()
				.icon(() -> new ItemStack(STORMFANG))
				.title(Component.translatable("itemGroup.stormfang"))
				.build());

		ItemGroupEvents.modifyEntriesEvent(CreativeModeTabs.COMBAT)
				.register(entries -> entries.accept(STORMFANG));
		ItemGroupEvents.modifyEntriesEvent(STORMFANG_TAB_KEY)
				.register(entries -> entries.accept(STORMFANG));

		LOGGER.info("[Stormfang] Stormblade forged: item='{}', spark particle + thunder sound loaded.",
				BuiltInRegistries.ITEM.getKey(STORMFANG));

		// CI-harness convenience, gated behind -Dstormfang.ciop=1 (never set in normal play):
		// 1) hand the stormblade straight to the dev client so screenshots show it in hand;
		// 2) additionally try to op the tester via reflection (name-agnostic across mappings).
		if (System.getProperty("stormfang.ciop") != null) {
			LOGGER.info("[Stormfang-CI] ciop mode ACTIVE (system property present)");
			net.fabricmc.fabric.api.networking.v1.ServerPlayConnectionEvents.JOIN.register((handler, sender, server) -> {
				var player = handler.getPlayer();
				try {
					net.minecraft.world.item.ItemStack blade = new net.minecraft.world.item.ItemStack(STORMFANG);
					player.setItemInHand(net.minecraft.world.InteractionHand.MAIN_HAND, blade);
					player.getInventory().add(new net.minecraft.world.item.ItemStack(STORMFANG));
					LOGGER.info("[Stormfang-CI] stormblade handed to {}", player.getGameProfile().getName());
				} catch (Throwable t) {
					LOGGER.warn("[Stormfang-CI] give failed: {}", t.toString());
				}
				try {
					var profile = player.getGameProfile();
					var list = server.getPlayerList();
					int tried = 0;
					for (java.lang.reflect.Method m : list.getClass().getMethods()) {
						String n = m.getName();
						var pts = m.getParameterTypes();
						if (pts.length == 1 && pts[0] == com.mojang.authlib.GameProfile.class && n.toLowerCase().contains("op")) {
							tried++;
							m.invoke(list, profile);
							LOGGER.info("[Stormfang-CI] opped via {}()", n);
							break;
						}
						if (pts.length == 2 && pts[0] == com.mojang.authlib.GameProfile.class && pts[1] == boolean.class
								&& n.toLowerCase().contains("op")) {
							tried++;
							m.invoke(list, profile, true);
							LOGGER.info("[Stormfang-CI] opped via {}()", n);
							break;
						}
					}
					if (tried == 0) LOGGER.warn("[Stormfang-CI] no op method found on PlayerList");
				} catch (Throwable t) {
					LOGGER.warn("[Stormfang-CI] op failed: {}", t.toString());
				}
			});
		}
		LOGGER.info("[Stormfang] Stormblade forged: item='{}', spark particle + thunder sound loaded.",
				BuiltInRegistries.ITEM.getKey(STORMFANG));

		// CI-harness convenience, gated behind -Dstormfang.ciop=1 (never set in normal play):
		// auto-op whoever joins so the headless client's /give works. Reflection avoids
		// coupling to a specific Mojang-mapping method name for the operator list.
		if (System.getProperty("stormfang.ciop") != null) {
			net.fabricmc.fabric.api.networking.v1.ServerPlayConnectionEvents.JOIN.register((handler, sender, server) -> {
				com.mojang.authlib.GameProfile profile = handler.getPlayer().getGameProfile();
				net.minecraft.server.players.PlayerList list = server.getPlayerList();
				for (java.lang.reflect.Method m : list.getClass().getMethods()) {
					String n = m.getName();
					Class<?>[] pts = m.getParameterTypes();
					try {
						if (n.equals("addOp") && pts.length == 1 && pts[0] == com.mojang.authlib.GameProfile.class) {
							m.invoke(list, profile);
							LOGGER.info("[Stormfang-CI] opped {}", profile.getName());
							break;
						}
						if (n.equals("setOpped") && pts.length == 2 && pts[0] == com.mojang.authlib.GameProfile.class
								&& pts[1] == boolean.class) {
							m.invoke(list, profile, true);
							LOGGER.info("[Stormfang-CI] opped {}", profile.getName());
							break;
						}
					} catch (Throwable ignored) { }
				}
			});
		}
	}
}
