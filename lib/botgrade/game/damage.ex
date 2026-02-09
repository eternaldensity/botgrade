defmodule Botgrade.Game.Damage do
  alias Botgrade.Game.{Card, Robot}

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

  Returns {updated_defender, updated_target_card, card_damage_dealt, absorb_log_message}.
  """
  @spec apply_typed_damage(Robot.t(), Card.t(), non_neg_integer(), atom()) ::
          {Robot.t(), Card.t(), non_neg_integer(), String.t()}
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
    updated_card = %{target_card | current_hp: new_hp} |> Card.sync_damage_state()

    # Update defender's defense pools
    updated_defender = %{defender | plating: new_plating, shield: new_shield}

    # Build absorption message
    absorb_msg = build_absorb_msg(plating_absorbed, shield_absorbed)

    {updated_defender, updated_card, card_damage, absorb_msg}
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
