defmodule Botgrade.Game.DiceLogic do
  @moduledoc """
  Handles dice allocation and slot management for combat.

  This module manages:
  - Player dice allocation during power_up phase
  - Dice unallocation (returning dice to available pool)
  - AI dice allocation strategy for the enemy
  - Immediate card activation when all slots are filled
  """

  alias Botgrade.Game.{CombatState, Card, CardActivation, ElementLogic, VictoryLogic}

  @doc """
  Allocates a die to a card slot during the power_up phase.

  If all slots are filled after allocation, the card is immediately activated.

  Returns {:ok, updated_state} if successful, {:error, reason} if allocation fails.

  Validation checks:
  - Must be in power_up phase
  - Die index must be valid
  - Card must exist in hand
  - Card must not be destroyed
  - Card must not be fully activated already
  - Slot must exist on card
  - Slot must be empty
  - Die value must meet slot condition
  """
  @spec allocate_die(CombatState.t(), non_neg_integer(), String.t(), String.t()) ::
          {:ok, CombatState.t()} | {:error, String.t()}
  def allocate_die(%CombatState{phase: :power_up} = state, die_index, card_id, slot_id) do
    player = state.player

    with {:die, die} when not is_nil(die) <- {:die, Enum.at(player.available_dice, die_index)},
         {:card, card} when not is_nil(card) <- {:card, find_card_in_hand(player, card_id)},
         true <- card.damage != :destroyed || {:error, "Card is destroyed."},
         true <-
           not (card.type in [:weapon, :armor, :utility] and card_fully_activated?(card)) ||
             {:error, "Card already activated this turn."},
         {:slot, slot_idx, slot} when not is_nil(slot) <- find_slot(card, slot_id),
         true <- is_nil(slot.assigned_die) || {:error, "Slot already has a die."} do
      # Locked slot (Fused/Magnetic): consume die to unlock, don't assign or activate
      if Map.get(slot, :locked, false) do
        unlocked_slot = slot |> Map.delete(:locked) |> Map.put(:assigned_die, nil)
        updated_slots = List.replace_at(card.dice_slots, slot_idx, unlocked_slot)
        updated_card = %{card | dice_slots: updated_slots}

        player = %{
          player
          | available_dice: List.delete_at(player.available_dice, die_index),
            hand: replace_card(player.hand, card_id, updated_card)
        }

        state =
          %{state | player: player}
          |> add_log("Die consumed to unlock fused slot on #{card.name}.")

        {:ok, state}
      else
        # Normal allocation: validate condition
        unless Card.meets_condition?(slot.condition, die.value) do
          {:error, "Die doesn't meet slot condition."}
        else
          updated_slot = %{slot | assigned_die: die}
          updated_slots = List.replace_at(card.dice_slots, slot_idx, updated_slot)
          updated_card = %{card | dice_slots: updated_slots}

          # Blazing die: deal 1 damage to the card when placed
          {updated_card, _updated_die, blazing_log} =
            ElementLogic.process_blazing_die(updated_card, die)

          player = %{
            player
            | available_dice: List.delete_at(player.available_dice, die_index),
              hand: replace_card(player.hand, card_id, updated_card)
          }

          state = %{state | player: player}
          state = if blazing_log, do: add_log(state, blazing_log), else: state

          # Immediate activation: when all slots filled on a weapon/armor/utility, fire it now
          if all_slots_filled?(updated_card) and updated_card.type in [:weapon, :armor, :utility] do
            state =
              state
              |> CardActivation.activate_card(updated_card, :player)
              |> VictoryLogic.check_victory()

            {:ok, state}
          else
            {:ok, state}
          end
        end
      end
    else
      {:die, nil} -> {:error, "Invalid die index."}
      {:card, nil} -> {:error, "Card not found."}
      {:slot, _, nil} -> {:error, "Slot not found on card."}
      {:error, reason} -> {:error, reason}
    end
  end

  def allocate_die(_state, _die_index, _card_id, _slot_id),
    do: {:error, "Not in power up phase."}

  @doc """
  Removes a die from a card slot and returns it to the available dice pool.

  Only works during the power_up phase.

  Returns {:ok, updated_state} if successful, {:error, reason} if unallocation fails.
  """
  @spec unallocate_die(CombatState.t(), String.t(), String.t()) ::
          {:ok, CombatState.t()} | {:error, String.t()}
  def unallocate_die(%CombatState{phase: :power_up} = state, card_id, slot_id) do
    player = state.player

    with {:card, card} when not is_nil(card) <-
           {:card, find_card_in_hand(player, card_id)},
         {:slot, slot_idx, slot} when not is_nil(slot) <- find_slot(card, slot_id),
         true <- not is_nil(slot.assigned_die) || {:error, "Slot is empty."} do
      die = slot.assigned_die
      updated_slot = %{slot | assigned_die: nil}
      updated_slots = List.replace_at(card.dice_slots, slot_idx, updated_slot)
      updated_card = %{card | dice_slots: updated_slots}

      player = %{
        player
        | available_dice: player.available_dice ++ [die],
          hand: replace_card(player.hand, card_id, updated_card)
      }

      {:ok, %{state | player: player}}
    else
      {:card, nil} -> {:error, "Card not found."}
      {:slot, _, nil} -> {:error, "Slot not found."}
      {:error, reason} -> {:error, reason}
    end
  end

  def unallocate_die(_state, _card_id, _slot_id),
    do: {:error, "Not in power up phase."}

  @doc """
  AI dice allocation strategy for the enemy.

  Phase 1: Allocate dice to utilities first (beam_split, overcharge)
  Phase 2: Allocate remaining dice to weapons and armor (highest dice first)

  Returns the updated combat state with all dice allocated.
  """
  @spec ai_allocate_dice(CombatState.t()) :: CombatState.t()
  def ai_allocate_dice(state) do
    # Phase 1: Allocate dice to utility cards first and activate them
    # (beam_split creates more dice, overcharge boosts damage)
    state = ai_allocate_and_activate_utilities(state)

    # Phase 2: Allocate remaining dice to weapons and armor
    enemy = state.enemy
    sorted_dice = Enum.sort_by(enemy.available_dice, & &1.value, :desc)

    weapons =
      enemy.hand
      |> Enum.filter(&(&1.type == :weapon and &1.damage != :destroyed))

    armor_cards =
      enemy.hand
      |> Enum.filter(&(&1.type == :armor and &1.damage != :destroyed))

    {enemy, remaining_dice, log_entries} =
      assign_dice_to_cards(enemy, sorted_dice, weapons ++ armor_cards)

    enemy = %{enemy | available_dice: remaining_dice}
    state = %{state | enemy: enemy}
    Enum.reduce(log_entries, state, fn msg, s -> add_log(s, msg) end)
  end

  # --- Private Helpers ---

  defp ai_allocate_and_activate_utilities(state) do
    utility_cards =
      state.enemy.hand
      |> Enum.filter(&(&1.type == :utility and &1.damage != :destroyed and not card_fully_activated?(&1)))

    Enum.reduce(utility_cards, state, fn util_card, acc_state ->
      # Try to assign a die to the utility card's slot
      enemy = acc_state.enemy
      slot = hd(util_card.dice_slots)

      # If slot is locked, consume a die to unlock it first
      {acc_state, slot, util_card} =
        if Map.get(slot, :locked, false) and enemy.available_dice != [] do
          [_die | rest] = enemy.available_dice
          unlocked_slot = slot |> Map.delete(:locked) |> Map.put(:assigned_die, nil)
          updated_card = %{util_card | dice_slots: [unlocked_slot]}
          enemy = %{enemy | hand: replace_card(enemy.hand, util_card.id, updated_card), available_dice: rest}
          acc_state = %{acc_state | enemy: enemy}
          acc_state = add_log(acc_state, "Enemy uses die to unlock fused slot on #{util_card.name}.")
          {acc_state, unlocked_slot, updated_card}
        else
          {acc_state, slot, util_card}
        end

      # Skip if slot is still locked (no dice to unlock)
      if Map.get(slot, :locked, false) do
        acc_state
      else
        enemy = acc_state.enemy

        best_die =
          if util_card.properties.utility_ability == :overcharge do
            enemy.available_dice
            |> Enum.with_index()
            |> Enum.filter(fn {d, _} -> Card.meets_condition?(slot.condition, d.value) end)
            |> Enum.sort_by(fn {d, _} -> d.value end)
            |> List.first()
          else
            enemy.available_dice
            |> Enum.with_index()
            |> Enum.filter(fn {d, _} -> Card.meets_condition?(slot.condition, d.value) end)
            |> Enum.sort_by(fn {d, _} -> d.value end, :desc)
            |> List.first()
          end

        case best_die do
          nil ->
            acc_state

          {die, die_idx} ->
            updated_slot = %{slot | assigned_die: die}
            updated_card = %{util_card | dice_slots: [updated_slot]}

            # Blazing self-damage
            {updated_card, _die, blazing_log} =
              ElementLogic.process_blazing_die(updated_card, die)

            enemy = %{
              enemy
              | hand: replace_card(enemy.hand, util_card.id, updated_card),
                available_dice: List.delete_at(enemy.available_dice, die_idx)
            }

            acc_state = %{acc_state | enemy: enemy}
            acc_state = add_log(acc_state, "Enemy assigns die [#{die.value}] to #{util_card.name}.")
            acc_state = if blazing_log, do: add_log(acc_state, blazing_log), else: acc_state

            CardActivation.activate_utility(acc_state, updated_card, :enemy)
        end
      end
    end)
  end

  defp assign_dice_to_cards(robot, dice, cards) do
    Enum.reduce(cards, {robot, dice, []}, fn card, {robot_acc, dice_acc, logs} ->
      Enum.reduce(card.dice_slots, {robot_acc, dice_acc, logs}, fn slot, {r, d, l} ->
        case d do
          [] ->
            {r, d, l}

          [die | rest] ->
            cond do
              # Locked slot (Fused): consume die to unlock
              is_nil(slot.assigned_die) and Map.get(slot, :locked, false) ->
                unlocked_slot = slot |> Map.delete(:locked) |> Map.put(:assigned_die, nil)

                updated_slots =
                  Enum.map(card.dice_slots, fn s ->
                    if s.id == slot.id, do: unlocked_slot, else: s
                  end)

                updated_card = %{card | dice_slots: updated_slots}
                hand = replace_card(r.hand, card.id, updated_card)
                r = %{r | hand: hand}

                {r, rest, l ++ ["Enemy uses die to unlock fused slot on #{card.name}."]}

              # Normal allocation
              is_nil(slot.assigned_die) and Card.meets_condition?(slot.condition, die.value) ->
                updated_slot = %{slot | assigned_die: die}

                updated_slots =
                  Enum.map(card.dice_slots, fn s ->
                    if s.id == slot.id, do: updated_slot, else: s
                  end)

                updated_card = %{card | dice_slots: updated_slots}

                # Blazing self-damage
                {updated_card, _die, blazing_log} =
                  ElementLogic.process_blazing_die(updated_card, die)

                hand = replace_card(r.hand, card.id, updated_card)
                r = %{r | hand: hand}

                extra_logs = if blazing_log, do: [blazing_log], else: []

                {r, rest,
                 l ++ ["Enemy assigns die [#{die.value}] to #{card.name}."] ++ extra_logs}

              true ->
                {r, d, l}
            end
        end
      end)
    end)
  end

  defp find_card_in_hand(robot, card_id) do
    Enum.find(robot.hand, &(&1.id == card_id))
  end

  defp find_slot(card, slot_id) do
    case Enum.find_index(card.dice_slots, &(&1.id == slot_id)) do
      nil -> {:slot, nil, nil}
      idx -> {:slot, idx, Enum.at(card.dice_slots, idx)}
    end
  end

  defp replace_card(cards, card_id, updated_card) do
    Enum.map(cards, fn
      %Card{id: ^card_id} -> updated_card
      card -> card
    end)
  end

  defp all_slots_filled?(card) do
    card.dice_slots != [] and Enum.all?(card.dice_slots, &(&1.assigned_die != nil))
  end

  defp card_fully_activated?(card) do
    max_per_turn = Map.get(card.properties, :max_activations_per_turn)

    if max_per_turn do
      Map.get(card.properties, :activations_this_turn, 0) >= max_per_turn
    else
      Map.get(card.properties, :activated_this_turn, false)
    end
  end

  defp add_log(state, message) do
    %{state | log: [message | state.log]}
  end
end
