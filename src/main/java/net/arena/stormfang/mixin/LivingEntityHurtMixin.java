package net.arena.stormfang.mixin;

import net.arena.stormfang.StormFx;
import net.arena.stormfang.StormfangMod;
import net.minecraft.server.level.ServerLevel;
import net.minecraft.world.damagesource.DamageSource;
import net.minecraft.world.entity.EntityType;
import net.minecraft.world.entity.LivingEntity;
import net.minecraft.world.entity.LightningBolt;
import net.minecraft.world.entity.player.Player;
import net.minecraft.world.level.Level;
import net.minecraft.world.phys.Vec3;
import org.spongepowered.asm.mixin.Mixin;
import org.spongepowered.asm.mixin.injection.At;
import org.spongepowered.asm.mixin.injection.Inject;
import org.spongepowered.asm.mixin.injection.callback.CallbackInfo;

/**
 * Every hit with Stormfang crackles with electricity; 35% chance to summon a bolt
 * on the victim and knock it into the air ("storm proc").
 */
@Mixin(LivingEntity.class)
public class LivingEntityHurtMixin {
	// 1.21.2+: LivingEntity#hurt(DamageSource,float) was split into hurtServer(ServerLevel,...)
	@Inject(method = "hurtServer(Lnet/minecraft/server/level/ServerLevel;Lnet/minecraft/world/damagesource/DamageSource;F)Z", at = @At("HEAD"))
	private void stormfang$stormOnHit(ServerLevel serverLevel, DamageSource source, float amount, CallbackInfo ci) {
		LivingEntity self = (LivingEntity) (Object) this;
		Level level = self.level();
		if (!(source.getEntity() instanceof Player attacker)) {
			return;
		}
		if (!attacker.getMainHandItem().is(StormfangMod.STORMFANG)) {
			return;
		}

		Vec3 p = self.position();
		StormFx.hitZap(serverLevel, p, self.getBbHeight());

		if (level.getRandom().nextFloat() < 0.35F) {
			LightningBolt bolt = new LightningBolt(EntityType.LIGHTNING_BOLT, level);
			bolt.setPos(self.getX(), self.getY() + 0.4, self.getZ());
			level.addFreshEntity(bolt);
			StormFx.thunderStrike(serverLevel, p.add(0.0, 0.3, 0.0));
			self.push(0.0, 0.45, 0.0);
			StormfangMod.LOGGER.info("[Stormfang] Storm proc on '{}' (hit for {} dmg)",
					self.getName().getString(), String.format("%.1f", amount));
		}
	}
}
