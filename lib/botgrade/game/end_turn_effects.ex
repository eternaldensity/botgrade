defmodule Botgrade.Game.EndTurnEffects do
  @moduledoc """
  Handles end-of-turn weapon effects in combat.

  Certain weapons have special effects that trigger at the end of a turn:
  - Plasma Lobber: Deals damage based on unused dice
  - Lithium Mode: Destroys depleted batteries to deal energy damage
  """

  alias Botgrade.Game.{CombatState, Card, Damage, Targeting}

  @doc """
  Processes all end-of-turn weapon effects for a combatant.

  Finds all installed weapons with end_of_turn_effect properties
  and processes each one in order.

  Returns the updated combat state.
  """
  @spec process_end_of_turn_weapons(CombatState.t(), :player | :enemy) :: CombatState.t()
  def process_end_of_turn_weapons(state, who) do
    {combatant, _opponent} = get_combatants(state, who)

    # Find all installed end-of-turn effect weapons that aren't destroyed
    eot_weapons =
      combatant.installed
      |> Enum.filter(&(&1.type == :weapon))
      |> Enum.filter(&(&1.damage != :destroyed))
      |> Enum.filter(&Map.has_key?(&1.properties, :end_of_turn_effect))

    Enum.reduce(eot_weapons, state, fn weapon, acc_state ->
      process_end_of_turn_weapon(acc_state, weapon, who)
    end)
  end

  @doc """
  Processes a specific end-of-turn weapon effect.

  Supports:
  - :plasma_lobber - Deals 2 damage per unused die
  - :lithium_mode - Destroys depleted batteries to deal 5 energy damage each

  Returns the updated combat state.
  """
  @spec process_end_of_turn_weapon(CombatState.t(), Card.t(), :player | :enemy) ::
          CombatState.t()
  def process_end_of_turn_weapon(state, weapon, who) do
    {combatant, opponent} = get_combatants(state, who)
    effect = weapon.properties.end_of_turn_effect

    case effect do
      :plasma_lobber ->
        process_plasma_lobber(state, weapon, who, combatant, opponent)

      :lithium_mode ->
        process_lithium_mode(state, weapon, who, combatant, opponent)

      _ ->
        state
    end
  end

  # --- Private Helpers ---

  defp process_plasma_lobber(state, weapon, who, combatant, opponent) do
    unused_dice_count = length(combatant.available_dice)
    damage = unused_dice_count * 2

    if damage > 0 do
      targetable = Targeting.targetable_cards(opponent)
      target = Targeting.select_target(weapon.properties.targeting_profile, targetable)

      if target do
        {updated_opponent, updated_target, card_dmg, absorb_msg} =
          Damage.apply_typed_damage(opponent, target, damage, :plasma)

        # Update the target card in the appropriate zone
        updated_opponent = update_card_in_zones(updated_opponent, updated_target.id, updated_target)

        state = put_combatants(state, who, combatant, updated_opponent)

        add_log(
          state,
          "#{weapon.name}: #{unused_dice_count} unused dice → #{damage} plasma damage to #{updated_target.name} (#{card_dmg} dealt)#{absorb_msg}!"
        )
      else
        state
      end
    else
      state
    end
  end

  defp process_lithium_mode(state, weapon, who, combatant, opponent) do
    # Find all batteries in hand with no remaining charges
    depleted_batteries =
      combatant.hand
      |> Enum.filter(&(&1.type == :battery))
      |> Enum.filter(&(&1.damage != :destroyed))
      |> Enum.filter(&(&1.properties.remaining_activations == 0))

    if length(depleted_batteries) > 0 do
      # Deal 5 energy damage per depleted battery
      total_damage = length(depleted_batteries) * 5

      targetable = Targeting.targetable_cards(opponent)
      target = Targeting.select_target(weapon.properties.targeting_profile, targetable)

      {state, target_name} =
        if target do
          {updated_opponent, updated_target, card_dmg, absorb_msg} =
            Damage.apply_typed_damage(opponent, target, total_damage, :energy)

          # Update the target card in the appropriate zone
          updated_opponent =
            update_card_in_zones(updated_opponent, updated_target.id, updated_target)

          state = put_combatants(state, who, combatant, updated_opponent)
          {state, "#{updated_target.name} (#{card_dmg} dealt)#{absorb_msg}"}
        else
          {state, nil}
        end

      # Destroy the depleted batteries
      battery_names = Enum.map_join(depleted_batteries, ", ", & &1.name)
      battery_ids = Enum.map(depleted_batteries, & &1.id)

      {combatant, _} = get_combatants(state, who)

      combatant = %{
        combatant
        | hand: Enum.reject(combatant.hand, &(&1.id in battery_ids)),
          discard: combatant.discard ++ Enum.map(depleted_batteries, &%{&1 | damage: :destroyed})
      }

      {_, opponent} = get_combatants(state, who)
      state = put_combatants(state, who, combatant, opponent)

      if target_name do
        add_log(
          state,
          "#{weapon.name}: Destroyed #{length(depleted_batteries)} depleted batteries (#{battery_names}) → #{total_damage} energy damage to #{target_name}!"
        )
      else
        add_log(
          state,
          "#{weapon.name}: Destroyed #{length(depleted_batteries)} depleted batteries (#{battery_names})."
        )
      end
    else
      state
    end
  end

  defp update_card_in_zones(robot, card_id, updated_card) do
    cond do
      Enum.any?(robot.installed, &(&1.id == card_id)) ->
        %{robot | installed: replace_card(robot.installed, card_id, updated_card)}

      Enum.any?(robot.hand, &(&1.id == card_id)) ->
        %{robot | hand: replace_card(robot.hand, card_id, updated_card)}

      true ->
        robot
    end
  end

  defp replace_card(cards, card_id, updated_card) do
    Enum.map(cards, fn
      %Card{id: ^card_id} -> updated_card
      card -> card
    end)
  end

  defp get_combatants(state, :player), do: {state.player, state.enemy}
  defp get_combatants(state, :enemy), do: {state.enemy, state.player}

  defp put_combatants(state, :player, attacker, defender),
    do: %{state | player: attacker, enemy: defender}

  defp put_combatants(state, :enemy, attacker, defender),
    do: %{state | enemy: attacker, player: defender}

  defp add_log(state, message) do
    %{state | log: [message | state.log]}
  end
end
