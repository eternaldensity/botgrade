defmodule Botgrade.Game.BatteryLogic do
  @moduledoc """
  Handles battery activation logic for combat.

  This module manages battery card activation, including:
  - Damage penalties for damaged batteries
  - Dice rolling and activation tracking
  - Overclock handling (allowing batteries to activate twice)
  """

  alias Botgrade.Game.{CombatState, Card, Dice}

  @doc """
  Activates a battery card in the player's hand during the power_up phase.

  Returns {:ok, updated_state} if successful, {:error, reason} if activation fails.

  Activation requirements:
  - Must be in power_up phase
  - Card must be a battery
  - Battery must not be destroyed
  - Battery must have remaining activations
  - Battery must not have been activated this turn (unless overclocked)
  """
  @spec activate_battery(CombatState.t(), String.t()) ::
          {:ok, CombatState.t()} | {:error, String.t()}
  def activate_battery(%CombatState{phase: :power_up} = state, card_id) do
    case find_card_in_hand(state.player, card_id) do
      nil ->
        {:error, "Card not found in hand."}

      %Card{type: :battery} = card ->
        remaining = card.properties.remaining_activations

        cond do
          card.damage == :destroyed ->
            {:error, "Card is destroyed."}

          remaining <= 0 ->
            {:error, "Battery is depleted."}

          Map.get(card.properties, :activated_this_turn, false) ->
            {:error, "Battery already activated this turn."}

          true ->
            dice = Dice.roll(card.properties.dice_count, card.properties.die_sides)

            {dice, penalty_msg} =
              if card.damage == :damaged do
                apply_battery_damage_penalty(dice, card.properties.die_sides)
              else
                {dice, ""}
              end

            dice_str = Enum.map_join(dice, ", ", fn d -> "#{d.value}" end)

            updated_card = %{
              card
              | properties:
                  card.properties
                  |> Map.put(:remaining_activations, remaining - 1)
                  |> Map.put(:activated_this_turn, true)
            }

            player = state.player
            hand = replace_card(player.hand, card_id, updated_card)
            available_dice = player.available_dice ++ dice

            player = %{player | hand: hand, available_dice: available_dice}

            state =
              %{state | player: player}
              |> add_log("Activated #{card.name}: rolled [#{dice_str}].#{penalty_msg}")

            # Overclock: allow this battery to activate again
            state =
              if state.overclock_active do
                player = state.player
                bat = find_card_in_hand(player, card_id)
                cleared = %{bat | properties: Map.delete(bat.properties, :activated_this_turn)}
                player = %{player | hand: replace_card(player.hand, card_id, cleared)}

                %{state | player: player, overclock_active: false}
                |> add_log("Overclock: #{card.name} can activate again!")
              else
                state
              end

            {:ok, state}
        end

      _other ->
        {:error, "That card is not a battery."}
    end
  end

  def activate_battery(_state, _card_id), do: {:error, "Not in power up phase."}

  @doc """
  Activates an enemy battery card.

  This is used during the enemy turn to automatically activate batteries.
  Updates the battery's remaining activations and adds rolled dice to available_dice.

  Returns the updated combat state.
  """
  @spec activate_enemy_battery(CombatState.t(), Card.t()) :: CombatState.t()
  def activate_enemy_battery(state, battery) do
    dice = Dice.roll(battery.properties.dice_count, battery.properties.die_sides)

    {dice, penalty_msg} =
      if battery.damage == :damaged do
        apply_battery_damage_penalty(dice, battery.properties.die_sides)
      else
        {dice, ""}
      end

    dice_str = Enum.map_join(dice, ", ", fn d -> "#{d.value}" end)

    updated_battery = %{
      battery
      | properties: %{
          battery.properties
          | remaining_activations: battery.properties.remaining_activations - 1
        }
    }

    enemy = state.enemy
    hand = replace_card(enemy.hand, battery.id, updated_battery)
    enemy = %{enemy | hand: hand, available_dice: enemy.available_dice ++ dice}

    %{state | enemy: enemy}
    |> add_log("Enemy activates #{battery.name}: rolled [#{dice_str}].#{penalty_msg}")
  end

  @doc """
  Applies damage penalty to battery dice rolls.

  For damaged batteries:
  - Multi-die batteries: lose one die
  - Single-die batteries: cap die value at (die_sides - 2), minimum 1

  Returns {updated_dice, penalty_message}.
  """
  @spec apply_battery_damage_penalty([map()], non_neg_integer()) :: {[map()], String.t()}
  def apply_battery_damage_penalty(dice, die_sides) do
    original_count = length(dice)

    if original_count > 1 do
      reduced = Enum.take(dice, original_count - 1)
      lost = original_count - length(reduced)
      {reduced, " (#{lost} die lost - damaged)"}
    else
      # Single-die battery: downgrade die value instead (cap at die_sides - 2, minimum 1)
      downgraded =
        Enum.map(dice, fn d ->
          %{d | value: max(1, min(d.value, die_sides - 2))}
        end)

      {downgraded, " (die capped at #{die_sides - 2} - damaged)"}
    end
  end

  # --- Private Helpers ---

  defp find_card_in_hand(robot, card_id) do
    Enum.find(robot.hand, &(&1.id == card_id))
  end

  defp replace_card(cards, card_id, updated_card) do
    Enum.map(cards, fn
      %Card{id: ^card_id} -> updated_card
      card -> card
    end)
  end

  defp add_log(state, message) do
    %{state | log: [message | state.log]}
  end
end
