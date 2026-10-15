package net.arena.stormfang;

import net.arena.stormfang.item.StormfangItem;
import net.minecraft.core.particles.ParticleTypes;
import net.minecraft.server.level.ServerLevel;
import net.minecraft.world.phys.Vec3;

/** Server-side particle bursts; visible to every nearby client, no extra packets needed. */
public final class StormFx {
	private StormFx() {
	}

	/** Big burst at the Thunderclap strike point. */
	public static void thunderStrike(ServerLevel level, Vec3 p) {
		level.sendParticles(ParticleTypes.ELECTRIC_SPARK,
				p.x, p.y + 0.7, p.z, 70, 1.3, 1.6, 1.3, 0.4);
		level.sendParticles(StormfangMod.STORM_SPARK,
				p.x, p.y + 1.0, p.z, 30, 1.1, 1.8, 1.1, 0.05);
		level.sendParticles(ParticleTypes.END_ROD,
				p.x, p.y + 0.4, p.z, 25, 1.4, 0.9, 1.4, 0.02);
		level.sendParticles(ParticleTypes.LARGE_SMOKE,
				p.x, p.y + 0.2, p.z, 12, 0.8, 0.4, 0.8, 0.04);
	}

	/** Small zap around an entity hit by the blade. */
	public static void hitZap(ServerLevel level, Vec3 p, float entityHeight) {
		level.sendParticles(ParticleTypes.ELECTRIC_SPARK,
				p.x, p.y + entityHeight * 0.6, p.z, 18, 0.45, 0.6, 0.45, 0.1);
		level.sendParticles(StormfangMod.STORM_SPARK,
				p.x, p.y + entityHeight * 0.75 + 0.2, p.z, 8, 0.35, 0.5, 0.35, 0.04);
	}
}
