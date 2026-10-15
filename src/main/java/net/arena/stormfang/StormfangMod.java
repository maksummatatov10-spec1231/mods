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
	}
}
