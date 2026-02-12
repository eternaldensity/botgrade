defmodule Botgrade.Game.Damage do
  alias Botgrade.Game.{Card, Robot, Targeting}

  @max_splash_depth 10

  # Defense effectiveness: {plating_multiplier, shield_multiplier}
  # Kinetic: plating blocks fully, shields block poorly
  # Energy: shields block fully, plating blocks poorly
  # Plasma: bypasses both, but does half damage to chassis
  @defense_matrix %{
    kinetic: {1.0, 0.25},
    energy: {0.25, 1.0},
    plasma: {0.0, 0.0}
  }

  @doc """
  Applies typed damage to a defender's target card, accounting for defense interactions.

  Returns {updated_defender, updated_target_card, card_damage_dealt, absorb_log_message, overkill}.
  """
  @spec apply_typed_damage(Robot.t(), Card.t(), non_neg_integer(), atom()) ::
          {Robot.t(), Card.t(), non_neg_integer(), String.t(), non_neg_integer()}
  def apply_typed_damage(defender, target_card, raw_damage, damage_type) do
    {plating_eff, shield_eff} = Map.get(@defense_matrix, damage_type, {0.5, 0.5})

    # Plating absorption pass
    {remaining, plating_absorbed, new_plating} =
      absorb(raw_damage, defender.plating, plating_eff)

    # Shield absorption pass
    {remaining, shield_absorbed, new_shield} =
      absorb(remaining, defender.shield, shield_eff)

    # Plasma does half damage to chassis cards
    card_damage =
      if damage_type == :plasma and target_card.type == :chassis do
        max(1, div(remaining, 2))
      else
        remaining
      end

    # Apply damage to target card
    new_hp = max(0, target_card.current_hp - card_damage)
    overkill = max(0, card_damage - target_card.current_hp)

    updated_card =
      %{target_card | current_hp: new_hp}
      |> Card.sync_damage_state()
      |> maybe_store_overkill(overkill)

    # Update defender's defense pools
    updated_defender = %{defender | plating: new_plating, shield: new_shield}

    # Build absorption message
    absorb_msg = build_absorb_msg(plating_absorbed, shield_absorbed)

    {updated_defender, updated_card, card_damage, absorb_msg, overkill}
  end

  @doc """
  Applies untyped splash damage directly to a card's HP, bypassing all defenses.
  Used for overkill overflow damage.

  Returns {updated_card, actual_damage_dealt, overkill}.
  """
  @spec apply_splash_damage(Card.t(), non_neg_integer()) ::
          {Card.t(), non_neg_integer(), non_neg_integer()}
  def apply_splash_damage(target_card, splash_damage) do
    new_hp = max(0, target_card.current_hp - splash_damage)
    overkill = max(0, splash_damage - target_card.current_hp)

    updated_card =
      %{target_card | current_hp: new_hp}
      |> Card.sync_damage_state()
      |> maybe_store_overkill(overkill)

    {updated_card, splash_damage, overkill}
  end

  @doc """
  Resolves recursive splash damage from overkill hits.

  When damage dealt to a card is >= 2x the card's remaining HP, excess minus `depth`
  splashes to another random target. Each successive chain increases the subtraction
  by 1, naturally causing chains to peter out.

  Returns {updated_defender, splash_log_messages}.
  """
  @spec resolve_splash_chain(
          Robot.t(),
          non_neg_integer(),
          map() | nil,
          non_neg_integer()
        ) :: {Robot.t(), [String.t()]}
  def resolve_splash_chain(defender, splash_damage, _targeting_profile, depth)
      when splash_damage <= 0 or depth > @max_splash_depth do
    {defender, []}
  end

  def resolve_splash_chain(defender, splash_damage, targeting_profile, depth) do
    targetable = Targeting.targetable_cards(defender)

    case Targeting.select_target(targeting_profile, targetable) do
      nil ->
        {defender, []}

      target ->
        {updated_target, _actual, overkill} = apply_splash_damage(target, splash_damage)
        defender = update_card_in_zones(defender, target.id, updated_target)

        destroyed_msg = if updated_target.current_hp <= 0, do: " DESTROYED!", else: ""

        damaged_msg =
          if updated_target.damage == :damaged and target.damage != :damaged,
            do: " (damaged)",
            else: ""

        log_msg =
          "SPLASH! #{splash_damage} overflow damage hits #{target.name}." <>
            " #{splash_damage} to #{target.name}#{damaged_msg}#{destroyed_msg}"

        # Check for recursive splash: damage must be >= 2x target's original HP
        if overkill > 0 and splash_damage >= 2 * target.current_hp do
          next_splash = splash_damage - target.current_hp - (depth + 1)

          {defender, chain_logs} =
            resolve_splash_chain(defender, next_splash, targeting_profile, depth + 1)

          {defender, [log_msg | chain_logs]}
        else
          {defender, [log_msg]}
        end
    end
  end

  # Absorbs damage using a defense pool at a given effectiveness rate.
  # At eff=1.0, 1 pool point absorbs 1 damage point.
  # At eff=0.25, 4 pool points needed to absorb 1 damage point.
  # Returns {remaining_damage, damage_absorbed, new_pool}.
  defp absorb(damage, pool, eff) when eff == 0.0, do: {damage, 0, pool}

  defp absorb(damage, pool, eff) when pool > 0 and damage > 0 do
    max_absorbable = floor(pool * eff)
    absorbed = min(damage, max_absorbable)
    pool_consumed = if eff > 0, do: min(pool, ceil(absorbed / eff)), else: 0
    {damage - absorbed, absorbed, pool - pool_consumed}
  end

  defp absorb(damage, pool, _eff), do: {damage, 0, pool}

  defp update_card_in_zones(robot, card_id, updated_card) do
    %{
      robot
      | installed: replace_card(robot.installed, card_id, updated_card),
        hand: replace_card(robot.hand, card_id, updated_card)
    }
  end

  defp replace_card(cards, card_id, updated_card) do
    Enum.map(cards, fn
      %Card{id: ^card_id} -> updated_card
      card -> card
    end)
  end

  defp maybe_store_overkill(%Card{damage: :destroyed} = card, overkill) when overkill > 0 do
    %{card | properties: Map.put(card.properties, :overkill, overkill)}
  end

  defp maybe_store_overkill(card, _overkill), do: card

  defp build_absorb_msg(plating_absorbed, shield_absorbed) do
    parts =
      []
      |> then(fn p -> if plating_absorbed > 0, do: p ++ ["#{plating_absorbed} absorbed by plating"], else: p end)
      |> then(fn p -> if shield_absorbed > 0, do: p ++ ["#{shield_absorbed} absorbed by shields"], else: p end)

    if parts != [] do
      " (#{Enum.join(parts, ", ")})"
    else
      ""
    end
  end
end
