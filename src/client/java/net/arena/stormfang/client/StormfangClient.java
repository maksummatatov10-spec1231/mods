package net.arena.stormfang.client;

import net.arena.stormfang.StormfangMod;
import net.fabricmc.api.ClientModInitializer;
import net.fabricmc.fabric.api.client.particle.v1.ParticleFactoryRegistry;
import net.minecraft.client.particle.EndRodParticle;

public class StormfangClient implements ClientModInitializer {
	@Override
	public void onInitializeClient() {
		// our storm_spark reuses the elegant vanilla end-rod behaviour,
		// but with the custom star texture (see assets/stormfang/textures/particle)
		ParticleFactoryRegistry.getInstance().register(
				StormfangMod.STORM_SPARK, EndRodParticle.Provider::new);
	}
}
