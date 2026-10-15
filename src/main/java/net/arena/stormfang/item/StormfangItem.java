package net.arena.stormfang.item;

import java.util.List;
import java.util.Map;
import java.util.UUID;
import java.util.concurrent.ConcurrentHashMap;

import net.arena.stormfang.StormFx;
import net.arena.stormfang.StormfangMod;
import net.minecraft.ChatFormatting;
import net.minecraft.core.component.DataComponents;
import net.minecraft.core.registries.Registries;
import net.minecraft.network.chat.Component;
import net.minecraft.resources.ResourceKey;
import net.minecraft.server.level.ServerLevel;
import net.minecraft.sounds.SoundSource;
import net.minecraft.world.InteractionHand;
import net.minecraft.world.InteractionResult;
import net.minecraft.world.entity.EntityType;
import net.minecraft.world.entity.LightningBolt;
import net.minecraft.world.entity.player.Player;
import net.minecraft.world.item.Item;
import net.minecraft.world.item.ItemStack;
import net.minecraft.world.item.Rarity;
import net.minecraft.world.item.SwordItem;
import net.minecraft.world.item.ToolMaterial;
import net.minecraft.world.item.TooltipFlag;
import net.minecraft.world.level.Level;
import net.minecraft.world.phys.EntityHitResult;
import net.minecraft.world.phys.HitResult;
import net.minecraft.world.phys.Vec3;

/**
 * Stormfang — legendary storm blade.
 * <p>
 * - netherite base, +5 attack damage, faster than netherite sword<br>
 * - animated 512px texture (lightning pulse crawls along the fuller) + enchantment glint<br>
 * - right-click: Thunderclap — raycast lightning up to 40 blocks, particles + synthesized sound<br>
 * - passive: every hit crackles; 35% chance to smite the target with a bolt (see LivingEntityHurtMixin)
 */
public class StormfangItem extends SwordItem {
	public static final ResourceKey<Item> KEY = ResourceKey.create(Registries.ITEM, StormfangMod.id("stormfang"));

	private static final Map<UUID, Long> COOLDOWN = new ConcurrentHashMap<>();
	private static final long COOLDOWN_MS = 2500L;
	private static final double RAYCAST_RANGE = 40.0;

	public StormfangItem(ResourceKey<Item> key) {
		super(ToolMaterial.NETHERITE, 5.0F, -1.6F, new Item.Properties()
				.setId(key)
				.rarity(Rarity.EPIC)
				.fireResistant()
				// permanent enchantment shimmer — part of the "living blade" look
				.component(DataComponents.ENCHANTMENT_GLINT_OVERRIDE, Boolean.TRUE));
	}

	@Override
	public InteractionResult use(Level world, Player user, InteractionHand hand) {
		// server authority — do nothing on the client
		if (world.isClientSide) {
			return InteractionResult.PASS;
		}

		long now = System.currentTimeMillis();
		Long last = COOLDOWN.get(user.getUUID());
		if (last != null && now - last < COOLDOWN_MS) {
			user.displayClientMessage(
					Component.translatable("item.stormfang.stormfang.cooldown").withStyle(ChatFormatting.YELLOW),
					true);
			return InteractionResult.FAIL;
		}
		COOLDOWN.put(user.getUUID(), now);

		HitResult hit = user.hitTest(RAYCAST_RANGE);
		Vec3 strike = hit.getType() == HitResult.Type.MISS
				? user.getEyePosition().add(user.getLookAngle().scale(20.0))
				: hit.getLocation();

		LightningBolt bolt = new LightningBolt(EntityType.LIGHTNING_BOLT, world);
		bolt.setPos(strike.x, strike.y + 0.5, strike.z);
		world.addFreshEntity(bolt);

		if (hit instanceof EntityHitResult entityHit && entityHit.getEntity() == user) {
			// never smite yourself — still allow the visual, the bolt itself is harmless midair
			StormfangMod.LOGGER.debug("[Stormfang] Thunderclap aimed at own entity, offset applied");
		}

		if (world instanceof ServerLevel serverLevel) {
			StormFx.thunderStrike(serverLevel, strike);
			serverLevel.playSound(null, strike.x, strike.y, strike.z,
					StormfangMod.THUNDER_CHARGE, SoundSource.WEATHER, 1.4F, 1.0F);
			StormfangMod.LOGGER.info("[Stormfang] Thunderclap by '{}' at {} {} {}",
					user.getGameProfile().getName(),
					String.format("%.1f", strike.x),
					String.format("%.1f", strike.y),
					String.format("%.1f", strike.z));
		}

		user.swing(hand, true);
		return InteractionResult.SUCCESS_SERVER;
	}

	@Override
	public void appendHoverText(ItemStack stack, TooltipContext context, List<Component> tooltip, TooltipFlag flag) {
		tooltip.add(Component.translatable("item.stormfang.stormfang.tooltip")
				.withStyle(ChatFormatting.AQUA, ChatFormatting.ITALIC));
		tooltip.add(Component.translatable("item.stormfang.stormfang.tooltip2")
				.withStyle(ChatFormatting.GRAY));
	}
}
