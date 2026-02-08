defmodule Botgrade.Game.CombatLogic do
  alias Botgrade.Game.{CombatState, Robot, Card, Dice, Deck}

  @draw_count 5
  @enemy_draw_count 4

  # --- Initialization ---

  @spec new_combat(String.t(), [Card.t()], [Card.t()]) :: CombatState.t()
  def new_combat(combat_id, player_cards, enemy_cards) do
    %CombatState{
      id: combat_id,
      player: Robot.new("player", "Player", player_cards),
      enemy: Robot.new("enemy", "Enemy", enemy_cards),
      phase: :draw,
      turn_number: 1,
      log: ["Combat started!"]
    }
  end

  # --- Draw Phase ---

  @spec draw_phase(CombatState.t()) :: CombatState.t()
  def draw_phase(%CombatState{phase: :draw, turn_owner: :player} = state) do
    player = draw_cards(state.player, @draw_count)

    %{state | player: player, phase: :activate_batteries}
    |> add_log("Turn #{state.turn_number}: Drew #{length(player.hand)} cards.")
  end

  # --- Battery Activation ---

  @spec activate_battery(CombatState.t(), String.t()) ::
          {:ok, CombatState.t()} | {:error, String.t()}
  def activate_battery(%CombatState{phase: :activate_batteries} = state, card_id) do
    case find_card_in_hand(state.player, card_id) do
      nil ->
        {:error, "Card not found in hand."}

      %Card{type: :battery} = card ->
        remaining = card.properties.remaining_activations

        cond do
          remaining <= 0 ->
            {:error, "Battery is depleted."}

          Map.get(card.properties, :activated_this_turn, false) ->
            {:error, "Battery already activated this turn."}

          true ->
            dice =
              Dice.roll(card.properties.dice_count, card.properties.die_sides)

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
              |> add_log("Activated #{card.name}: rolled [#{dice_str}].")

            {:ok, state}
        end

      _other ->
        {:error, "That card is not a battery."}
    end
  end

  def activate_battery(_state, _card_id), do: {:error, "Not in battery activation phase."}

  @spec finish_activating(CombatState.t()) :: CombatState.t()
  def finish_activating(%CombatState{phase: :activate_batteries} = state) do
    %{state | phase: :allocate_dice}
    |> add_log("Battery activation complete. Allocate your dice.")
  end

  # --- Dice Allocation ---

  @spec allocate_die(CombatState.t(), non_neg_integer(), String.t(), String.t()) ::
          {:ok, CombatState.t()} | {:error, String.t()}
  def allocate_die(%CombatState{phase: :allocate_dice} = state, die_index, card_id, slot_id) do
    player = state.player

    with {:die, die} when not is_nil(die) <- {:die, Enum.at(player.available_dice, die_index)},
         {:card, card} when not is_nil(card) <- {:card, find_card_in_hand_or_play(player, card_id)},
         {:slot, slot_idx, slot} when not is_nil(slot) <- find_slot(card, slot_id),
         true <- is_nil(slot.assigned_die) || {:error, "Slot already has a die."},
         true <- Card.meets_condition?(slot.condition, die.value) || {:error, "Die doesn't meet slot condition."} do
      updated_slot = %{slot | assigned_die: die}
      updated_slots = List.replace_at(card.dice_slots, slot_idx, updated_slot)
      updated_card = %{card | dice_slots: updated_slots}

      player = %{
        player
        | available_dice: List.delete_at(player.available_dice, die_index),
          hand: replace_card(player.hand, card_id, updated_card),
          in_play: replace_card(player.in_play, card_id, updated_card)
      }

      {:ok, %{state | player: player}}
    else
      {:die, nil} -> {:error, "Invalid die index."}
      {:card, nil} -> {:error, "Card not found."}
      {:slot, _, nil} -> {:error, "Slot not found on card."}
      {:error, reason} -> {:error, reason}
    end
  end

  def allocate_die(_state, _die_index, _card_id, _slot_id),
    do: {:error, "Not in dice allocation phase."}

  @spec unallocate_die(CombatState.t(), String.t(), String.t()) ::
          {:ok, CombatState.t()} | {:error, String.t()}
  def unallocate_die(%CombatState{phase: :allocate_dice} = state, card_id, slot_id) do
    player = state.player

    with {:card, card} when not is_nil(card) <- {:card, find_card_in_hand_or_play(player, card_id)},
         {:slot, slot_idx, slot} when not is_nil(slot) <- find_slot(card, slot_id),
         true <- not is_nil(slot.assigned_die) || {:error, "Slot is empty."} do
      die = slot.assigned_die
      updated_slot = %{slot | assigned_die: nil}
      updated_slots = List.replace_at(card.dice_slots, slot_idx, updated_slot)
      updated_card = %{card | dice_slots: updated_slots}

      player = %{
        player
        | available_dice: player.available_dice ++ [die],
          hand: replace_card(player.hand, card_id, updated_card),
          in_play: replace_card(player.in_play, card_id, updated_card)
      }

      {:ok, %{state | player: player}}
    else
      {:card, nil} -> {:error, "Card not found."}
      {:slot, _, nil} -> {:error, "Slot not found."}
      {:error, reason} -> {:error, reason}
    end
  end

  @spec finish_allocating(CombatState.t()) :: CombatState.t()
  def finish_allocating(%CombatState{phase: :allocate_dice} = state) do
    %{state | phase: :resolve}
  end

  # --- Resolve Phase ---

  @spec resolve(CombatState.t()) :: CombatState.t()
  def resolve(%CombatState{phase: :resolve} = state) do
    state
    |> resolve_armor(:player)
    |> resolve_weapons(:player)
    |> cleanup_turn(:player)
    |> check_victory()
    |> maybe_transition_to_enemy()
  end

  defp maybe_transition_to_enemy(%CombatState{result: :ongoing} = state) do
    %{state | phase: :enemy_turn}
  end

  defp maybe_transition_to_enemy(state), do: state

  # --- Enemy Turn ---

  @spec enemy_turn(CombatState.t()) :: CombatState.t()
  def enemy_turn(%CombatState{phase: :enemy_turn} = state) do
    enemy = draw_cards(state.enemy, @enemy_draw_count)
    state = %{state | enemy: enemy} |> add_log("Enemy draws #{length(enemy.hand)} cards.")

    state = activate_all_batteries(state, :enemy)
    state = ai_allocate_dice(state)

    state
    |> resolve_armor(:enemy)
    |> resolve_weapons(:enemy)
    |> cleanup_turn(:enemy)
    |> check_victory()
    |> next_turn()
  end

  # --- Private Helpers ---

  defp draw_cards(robot, count) do
    {deck, discard} =
      if length(robot.deck) < count and length(robot.discard) > 0 do
        {Deck.shuffle_discard_into_deck(robot.deck, robot.discard), []}
      else
        {robot.deck, robot.discard}
      end

    {drawn, remaining} = Deck.draw(deck, count)
    %{robot | deck: remaining, hand: robot.hand ++ drawn, discard: discard}
  end

  defp find_card_in_hand(robot, card_id) do
    Enum.find(robot.hand, &(&1.id == card_id))
  end

  defp find_card_in_hand_or_play(robot, card_id) do
    Enum.find(robot.hand, &(&1.id == card_id)) ||
      Enum.find(robot.in_play, &(&1.id == card_id))
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

  defp resolve_weapons(state, who) do
    {attacker, defender} = get_combatants(state, who)
    who_name = if who == :player, do: "You", else: "Enemy"

    weapons =
      (attacker.hand ++ attacker.in_play)
      |> Enum.filter(&(&1.type == :weapon))
      |> Enum.filter(fn card ->
        Enum.any?(card.dice_slots, fn slot -> slot.assigned_die != nil end)
      end)

    {defender, log_entries} =
      Enum.reduce(weapons, {defender, []}, fn weapon, {def_acc, logs} ->
        total_damage =
          weapon.dice_slots
          |> Enum.filter(&(&1.assigned_die != nil))
          |> Enum.reduce(weapon.properties.damage_base, fn slot, acc ->
            acc + slot.assigned_die.value
          end)

        absorbed = min(total_damage, def_acc.shield)
        net_damage = total_damage - absorbed
        new_shield = def_acc.shield - absorbed
        new_hp = max(0, def_acc.current_hp - net_damage)

        log_msg =
          if absorbed > 0 do
            "#{who_name} fires #{weapon.name} for #{total_damage} damage (#{absorbed} absorbed by shields). #{net_damage} damage dealt."
          else
            "#{who_name} fires #{weapon.name} for #{total_damage} damage."
          end

        {%{def_acc | current_hp: new_hp, shield: new_shield}, logs ++ [log_msg]}
      end)

    state = put_combatants(state, who, attacker, defender)
    Enum.reduce(log_entries, state, fn msg, s -> add_log(s, msg) end)
  end

  defp resolve_armor(state, who) do
    {combatant, _defender} = get_combatants(state, who)
    who_name = if who == :player, do: "You", else: "Enemy"

    armor_cards =
      (combatant.hand ++ combatant.in_play)
      |> Enum.filter(&(&1.type == :armor))
      |> Enum.filter(fn card ->
        Enum.any?(card.dice_slots, fn slot -> slot.assigned_die != nil end)
      end)

    {total_shield, log_entries} =
      Enum.reduce(armor_cards, {0, []}, fn armor, {shield_acc, logs} ->
        shield_value =
          armor.dice_slots
          |> Enum.filter(&(&1.assigned_die != nil))
          |> Enum.reduce(armor.properties.shield_base, fn slot, acc ->
            acc + slot.assigned_die.value
          end)

        {shield_acc + shield_value, logs ++ ["#{who_name} activates #{armor.name}: #{shield_value} shield."]}
      end)

    combatant = %{combatant | shield: total_shield}

    state =
      if who == :player,
        do: %{state | player: combatant},
        else: %{state | enemy: combatant}

    Enum.reduce(log_entries, state, fn msg, s -> add_log(s, msg) end)
  end

  defp cleanup_turn(state, who) do
    {combatant, _} = get_combatants(state, who)

    # Clear dice from non-capacitor card slots
    hand_cards = clear_dice_from_cards(combatant.hand)
    in_play_cards = clear_dice_from_cards(combatant.in_play)

    all_cards = hand_cards ++ in_play_cards

    # Capacitors with stored dice stay in hand for next turn
    {charged_capacitors, to_discard} =
      Enum.split_with(all_cards, fn card ->
        card.type == :capacitor and Enum.any?(card.dice_slots, &(&1.assigned_die != nil))
      end)

    combatant = %{
      combatant
      | hand: charged_capacitors,
        discard: combatant.discard ++ to_discard,
        in_play: [],
        available_dice: [],
        shield: 0
    }

    if who == :player,
      do: %{state | player: combatant},
      else: %{state | enemy: combatant}
  end

  defp clear_dice_from_cards(cards) do
    Enum.map(cards, fn card ->
      card = reset_battery_flag(card)

      if card.type == :capacitor do
        card
      else
        updated_slots = Enum.map(card.dice_slots, &%{&1 | assigned_die: nil})
        %{card | dice_slots: updated_slots}
      end
    end)
  end

  defp reset_battery_flag(%Card{type: :battery} = card) do
    %{card | properties: Map.delete(card.properties, :activated_this_turn)}
  end

  defp reset_battery_flag(card), do: card

  defp check_victory(state) do
    cond do
      state.enemy.current_hp <= 0 ->
        %{state | result: :player_wins, phase: :ended}
        |> add_log("Enemy destroyed! You win!")

      state.player.current_hp <= 0 ->
        %{state | result: :enemy_wins, phase: :ended}
        |> add_log("You have been destroyed! Defeat.")

      true ->
        state
    end
  end

  defp next_turn(%CombatState{result: :ongoing} = state) do
    %{state | phase: :draw, turn_owner: :player, turn_number: state.turn_number + 1}
  end

  defp next_turn(state), do: state

  defp activate_all_batteries(state, :enemy) do
    batteries =
      state.enemy.hand
      |> Enum.filter(&(&1.type == :battery))
      |> Enum.filter(&(&1.properties.remaining_activations > 0))

    Enum.reduce(batteries, state, fn battery, acc_state ->
      dice = Dice.roll(battery.properties.dice_count, battery.properties.die_sides)
      dice_str = Enum.map_join(dice, ", ", fn d -> "#{d.value}" end)

      updated_battery = %{
        battery
        | properties: %{battery.properties | remaining_activations: battery.properties.remaining_activations - 1}
      }

      enemy = acc_state.enemy
      hand = replace_card(enemy.hand, battery.id, updated_battery)
      enemy = %{enemy | hand: hand, available_dice: enemy.available_dice ++ dice}

      %{acc_state | enemy: enemy}
      |> add_log("Enemy activates #{battery.name}: rolled [#{dice_str}].")
    end)
  end

  defp ai_allocate_dice(state) do
    enemy = state.enemy
    sorted_dice = Enum.sort_by(enemy.available_dice, & &1.value, :desc)

    weapons =
      enemy.hand
      |> Enum.filter(&(&1.type == :weapon))

    armor_cards =
      enemy.hand
      |> Enum.filter(&(&1.type == :armor))

    # Assign highest dice to weapons first, then armor
    {enemy, remaining_dice, log_entries} =
      assign_dice_to_cards(enemy, sorted_dice, weapons ++ armor_cards)

    enemy = %{enemy | available_dice: remaining_dice}
    state = %{state | enemy: enemy}
    Enum.reduce(log_entries, state, fn msg, s -> add_log(s, msg) end)
  end

  defp assign_dice_to_cards(robot, dice, cards) do
    Enum.reduce(cards, {robot, dice, []}, fn card, {robot_acc, dice_acc, logs} ->
      Enum.reduce(card.dice_slots, {robot_acc, dice_acc, logs}, fn slot, {r, d, l} ->
        case d do
          [] ->
            {r, d, l}

          [die | rest] ->
            if is_nil(slot.assigned_die) and Card.meets_condition?(slot.condition, die.value) do
              updated_slot = %{slot | assigned_die: die}

              updated_slots =
                Enum.map(card.dice_slots, fn s ->
                  if s.id == slot.id, do: updated_slot, else: s
                end)

              updated_card = %{card | dice_slots: updated_slots}
              hand = replace_card(r.hand, card.id, updated_card)
              r = %{r | hand: hand}

              {r, rest, l ++ ["Enemy assigns die [#{die.value}] to #{card.name}."]}
            else
              {r, d, l}
            end
        end
      end)
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
