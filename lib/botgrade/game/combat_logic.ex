defmodule Botgrade.Game.CombatLogic do
  alias Botgrade.Game.{CombatState, Robot, Card, Dice, Deck, ScavengeLogic, Targeting, Damage}

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

    %{state | player: player, phase: :power_up}
    |> add_log("Turn #{state.turn_number}: Drew #{length(player.hand)} cards.")
  end

  # --- Battery Activation (available during :power_up) ---

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
                original_count = length(dice)
                reduced = Enum.take(dice, max(1, original_count - 1))
                lost = original_count - length(reduced)

                msg =
                  if lost > 0,
                    do: " (#{lost} die lost - damaged)",
                    else: ""

                {reduced, msg}
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

            {:ok, state}
        end

      _other ->
        {:error, "That card is not a battery."}
    end
  end

  def activate_battery(_state, _card_id), do: {:error, "Not in power up phase."}

  # --- Dice Allocation (available during :power_up, with immediate activation) ---

  @spec allocate_die(CombatState.t(), non_neg_integer(), String.t(), String.t()) ::
          {:ok, CombatState.t()} | {:error, String.t()}
  def allocate_die(%CombatState{phase: :power_up} = state, die_index, card_id, slot_id) do
    player = state.player

    with {:die, die} when not is_nil(die) <- {:die, Enum.at(player.available_dice, die_index)},
         {:card, card} when not is_nil(card) <- {:card, find_card_in_hand_or_play(player, card_id)},
         true <- card.damage != :destroyed || {:error, "Card is destroyed."},
         {:slot, slot_idx, slot} when not is_nil(slot) <- find_slot(card, slot_id),
         true <- is_nil(slot.assigned_die) || {:error, "Slot already has a die."},
         true <-
           Card.meets_condition?(slot.condition, die.value) ||
             {:error, "Die doesn't meet slot condition."} do
      updated_slot = %{slot | assigned_die: die}
      updated_slots = List.replace_at(card.dice_slots, slot_idx, updated_slot)
      updated_card = %{card | dice_slots: updated_slots}

      player = %{
        player
        | available_dice: List.delete_at(player.available_dice, die_index),
          hand: replace_card(player.hand, card_id, updated_card),
          in_play: replace_card(player.in_play, card_id, updated_card)
      }

      state = %{state | player: player}

      # Immediate activation: when all slots filled on a weapon/armor, fire it now
      if all_slots_filled?(updated_card) and updated_card.type in [:weapon, :armor] do
        state = activate_card(state, updated_card, :player)
        {:ok, state}
      else
        {:ok, state}
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

  @spec unallocate_die(CombatState.t(), String.t(), String.t()) ::
          {:ok, CombatState.t()} | {:error, String.t()}
  def unallocate_die(%CombatState{phase: :power_up} = state, card_id, slot_id) do
    player = state.player

    with {:card, card} when not is_nil(card) <-
           {:card, find_card_in_hand_or_play(player, card_id)},
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

  # --- End Turn ---

  @spec end_turn(CombatState.t()) :: CombatState.t()
  def end_turn(%CombatState{phase: :power_up} = state) do
    state
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

  # --- Immediate Card Activation (for player during :power_up) ---

  defp activate_card(state, card, who) do
    case card.type do
      :weapon -> activate_weapon(state, card, who)
      :armor -> activate_armor(state, card, who)
      _ -> state
    end
  end

  defp activate_weapon(state, weapon, who) do
    {attacker, defender} = get_combatants(state, who)
    who_name = if who == :player, do: "You", else: "Enemy"

    raw_damage = calculate_weapon_damage(weapon)
    total_damage = apply_damage_penalty(raw_damage, weapon)

    penalty_msg =
      if weapon.damage == :damaged and raw_damage != total_damage,
        do: " (halved from #{raw_damage} - damaged)",
        else: ""

    # Target selection via weapon's targeting profile
    targeting_profile = Map.get(weapon.properties, :targeting_profile)
    targetable = Targeting.targetable_cards(defender)

    {state, attacker, log_msg} =
      case Targeting.select_target(targeting_profile, targetable) do
        nil ->
          {state, attacker, "#{who_name} fires #{weapon.name} but finds no target!"}

        target ->
          damage_type = weapon.properties.damage_type

          {defender, updated_target, card_dmg, absorb_msg} =
            Damage.apply_typed_damage(defender, target, total_damage, damage_type)

          defender = update_card_in_zones(defender, target.id, updated_target)

          destroyed_msg = if updated_target.current_hp <= 0, do: " DESTROYED!", else: ""

          damaged_msg =
            if updated_target.damage == :damaged and target.damage != :damaged,
              do: " (damaged)",
              else: ""

          type_label = damage_type_label(damage_type)

          log_msg =
            "#{who_name} fires #{weapon.name} (#{type_label}) for #{total_damage}#{penalty_msg}" <>
              " -> hits #{target.name}#{absorb_msg}." <>
              " #{card_dmg} to #{target.name}#{damaged_msg}#{destroyed_msg}"

          state = put_combatants(state, who, attacker, defender)

          state = %{
            state
            | last_attack_result: %{weapon: weapon.name, target: target.id, damage: card_dmg}
          }

          {state, attacker, log_msg}
      end

    # Store result on card, then clear slots and move to in_play
    dice_used = Enum.map(weapon.dice_slots, & &1.assigned_die) |> Enum.reject(&is_nil/1)

    result_card =
      weapon
      |> clear_card_slots()
      |> Map.put(:last_result, %{type: :damage, value: total_damage, dice: dice_used})

    attacker = move_card_to_in_play(attacker, weapon.id, result_card)

    state =
      if who == :player,
        do: %{state | player: attacker},
        else: %{state | enemy: attacker}

    add_log(state, log_msg)
  end

  defp activate_armor(state, armor, who) do
    {combatant, _defender} = get_combatants(state, who)
    who_name = if who == :player, do: "You", else: "Enemy"

    raw_value =
      armor.dice_slots
      |> Enum.filter(&(&1.assigned_die != nil))
      |> Enum.reduce(armor.properties.shield_base, fn slot, acc ->
        acc + slot.assigned_die.value
      end)

    value = apply_damage_penalty(raw_value, armor)

    penalty_msg =
      if armor.damage == :damaged and raw_value != value,
        do: " (halved from #{raw_value} - damaged)",
        else: ""

    {combatant, log_msg} =
      case armor.properties.armor_type do
        :plating ->
          combatant = %{combatant | plating: combatant.plating + value}
          {combatant, "#{who_name} activates #{armor.name}: +#{value} plating#{penalty_msg}."}

        :shield ->
          combatant = %{combatant | shield: combatant.shield + value}
          {combatant, "#{who_name} activates #{armor.name}: +#{value} shield#{penalty_msg}."}
      end

    # Store result on card, then clear slots and move to in_play
    dice_used = Enum.map(armor.dice_slots, & &1.assigned_die) |> Enum.reject(&is_nil/1)
    result_type = armor.properties.armor_type

    result_card =
      armor
      |> clear_card_slots()
      |> Map.put(:last_result, %{type: result_type, value: value, dice: dice_used})

    combatant = move_card_to_in_play(combatant, armor.id, result_card)

    state =
      if who == :player,
        do: %{state | player: combatant},
        else: %{state | enemy: combatant}

    add_log(state, log_msg)
  end

  # --- Resolution helpers (used by enemy turn batch resolution) ---

  defp resolve_weapons(state, who) do
    {attacker, defender} = get_combatants(state, who)
    who_name = if who == :player, do: "You", else: "Enemy"

    weapons =
      (attacker.hand ++ attacker.in_play)
      |> Enum.filter(&(&1.type == :weapon))
      |> Enum.filter(fn card ->
        card.damage != :destroyed and
          Enum.any?(card.dice_slots, fn slot -> slot.assigned_die != nil end)
      end)

    {attacker, defender, log_entries} =
      Enum.reduce(weapons, {attacker, defender, []}, fn weapon, {att_acc, def_acc, logs} ->
        raw_damage = calculate_weapon_damage(weapon)
        total_damage = apply_damage_penalty(raw_damage, weapon)

        penalty_msg =
          if weapon.damage == :damaged and raw_damage != total_damage,
            do: " (halved from #{raw_damage} - damaged)",
            else: ""

        targeting_profile = Map.get(weapon.properties, :targeting_profile)
        targetable = Targeting.targetable_cards(def_acc)

        case Targeting.select_target(targeting_profile, targetable) do
          nil ->
            {att_acc, def_acc, logs ++ ["#{who_name} fires #{weapon.name} but finds no target!"]}

          target ->
            damage_type = weapon.properties.damage_type

            {def_acc, updated_target, card_dmg, absorb_msg} =
              Damage.apply_typed_damage(def_acc, target, total_damage, damage_type)

            def_acc = update_card_in_zones(def_acc, target.id, updated_target)

            destroyed_msg = if updated_target.current_hp <= 0, do: " DESTROYED!", else: ""

            damaged_msg =
              if updated_target.damage == :damaged and target.damage != :damaged,
                do: " (damaged)",
                else: ""

            type_label = damage_type_label(damage_type)

            log_msg =
              "#{who_name} fires #{weapon.name} (#{type_label}) for #{total_damage}#{penalty_msg}" <>
                " -> hits #{target.name}#{absorb_msg}." <>
                " #{card_dmg} to #{target.name}#{damaged_msg}#{destroyed_msg}"

            {att_acc, def_acc, logs ++ [log_msg]}
        end
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
        card.damage != :destroyed and
          Enum.any?(card.dice_slots, fn slot -> slot.assigned_die != nil end)
      end)

    {combatant, log_entries} =
      Enum.reduce(armor_cards, {combatant, []}, fn armor, {comb_acc, logs} ->
        raw_value =
          armor.dice_slots
          |> Enum.filter(&(&1.assigned_die != nil))
          |> Enum.reduce(armor.properties.shield_base, fn slot, acc ->
            acc + slot.assigned_die.value
          end)

        value = apply_damage_penalty(raw_value, armor)

        penalty_msg =
          if armor.damage == :damaged and raw_value != value,
            do: " (halved from #{raw_value} - damaged)",
            else: ""

        {comb_acc, log_msg} =
          case armor.properties.armor_type do
            :plating ->
              comb_acc = %{comb_acc | plating: comb_acc.plating + value}
              {comb_acc, "#{who_name} activates #{armor.name}: +#{value} plating#{penalty_msg}."}

            :shield ->
              comb_acc = %{comb_acc | shield: comb_acc.shield + value}
              {comb_acc, "#{who_name} activates #{armor.name}: +#{value} shield#{penalty_msg}."}
          end

        {comb_acc, logs ++ [log_msg]}
      end)

    state =
      if who == :player,
        do: %{state | player: combatant},
        else: %{state | enemy: combatant}

    Enum.reduce(log_entries, state, fn msg, s -> add_log(s, msg) end)
  end

  # --- Cleanup ---

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
        # Shield resets each turn, plating persists
        shield: 0
    }

    if who == :player,
      do: %{state | player: combatant},
      else: %{state | enemy: combatant}
  end

  # --- Victory / Defeat ---

  defp check_victory(state) do
    case {check_defeat(state.enemy), check_defeat(state.player)} do
      {{:defeated, reason}, _} ->
        %{state | result: :player_wins}
        |> add_log("Enemy defeated: #{defeat_message(reason)}")
        |> ScavengeLogic.begin_scavenge()

      {_, {:defeated, reason}} ->
        %{state | result: :enemy_wins, phase: :ended}
        |> add_log("You have been defeated: #{defeat_message(reason)}")

      _ ->
        state
    end
  end

  @spec check_defeat(Robot.t()) :: :alive | {:defeated, atom()}
  def check_defeat(robot) do
    all_cards = robot.installed ++ robot.deck ++ robot.hand ++ robot.discard ++ robot.in_play

    installed_alive =
      robot.installed
      |> Enum.filter(&(&1.current_hp != nil and &1.current_hp > 0))
      |> Enum.group_by(& &1.type)

    all_alive =
      all_cards
      |> Enum.filter(&(&1.current_hp != nil and &1.current_hp > 0))
      |> Enum.group_by(& &1.type)

    cond do
      # All chassis destroyed
      not Map.has_key?(installed_alive, :chassis) ->
        {:defeated, :chassis_destroyed}

      # All CPU destroyed (only if bot has CPU cards)
      has_type?(robot.installed, :cpu) and not Map.has_key?(installed_alive, :cpu) ->
        {:defeated, :cpu_destroyed}

      # All weapons AND locomotion destroyed
      not Map.has_key?(all_alive, :weapon) and not Map.has_key?(installed_alive, :locomotion) ->
        {:defeated, :disarmed_and_immobile}

      # All power generation destroyed/depleted
      power_exhausted?(all_cards) ->
        {:defeated, :power_failure}

      true ->
        :alive
    end
  end

  defp has_type?(cards, type), do: Enum.any?(cards, &(&1.type == type))

  defp power_exhausted?(all_cards) do
    batteries = Enum.filter(all_cards, &(&1.type == :battery))
    capacitors = Enum.filter(all_cards, &(&1.type == :capacitor))

    if batteries == [] and capacitors == [] do
      false
    else
      batteries_dead =
        Enum.all?(batteries, fn bat ->
          (bat.current_hp != nil and bat.current_hp <= 0) or
            Map.get(bat.properties, :remaining_activations, 0) <= 0
        end)

      capacitors_dead =
        Enum.all?(capacitors, fn cap ->
          cap.current_hp != nil and cap.current_hp <= 0
        end)

      batteries_dead and capacitors_dead
    end
  end

  defp defeat_message(:chassis_destroyed),
    do: "Structural failure! All chassis components destroyed."

  defp defeat_message(:cpu_destroyed), do: "System crash! All CPU modules destroyed."

  defp defeat_message(:disarmed_and_immobile),
    do: "Neutralized! All weapons and locomotion destroyed."

  defp defeat_message(:power_failure),
    do: "Power failure! All energy sources depleted or destroyed."

  # --- Private Helpers ---

  defp calculate_weapon_damage(weapon) do
    weapon.dice_slots
    |> Enum.filter(&(&1.assigned_die != nil))
    |> Enum.reduce(weapon.properties.damage_base, fn slot, acc ->
      acc + slot.assigned_die.value
    end)
  end

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

  defp all_slots_filled?(card) do
    card.dice_slots != [] and Enum.all?(card.dice_slots, &(&1.assigned_die != nil))
  end

  defp clear_card_slots(card) do
    updated_slots = Enum.map(card.dice_slots, &%{&1 | assigned_die: nil})
    %{card | dice_slots: updated_slots}
  end

  defp move_card_to_in_play(robot, card_id, cleared_card) do
    hand = Enum.reject(robot.hand, &(&1.id == card_id))
    in_play_without = Enum.reject(robot.in_play, &(&1.id == card_id))
    %{robot | hand: hand, in_play: in_play_without ++ [cleared_card]}
  end

  defp update_card_in_zones(robot, card_id, updated_card) do
    %{
      robot
      | installed: replace_card(robot.installed, card_id, updated_card),
        hand: replace_card(robot.hand, card_id, updated_card),
        in_play: replace_card(robot.in_play, card_id, updated_card)
    }
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

  defp apply_damage_penalty(value, %Card{damage: :intact}), do: value
  defp apply_damage_penalty(value, %Card{damage: :damaged}), do: max(0, div(value, 2))
  defp apply_damage_penalty(_value, %Card{damage: :destroyed}), do: 0

  defp next_turn(%CombatState{result: :ongoing} = state) do
    %{state | phase: :draw, turn_owner: :player, turn_number: state.turn_number + 1}
  end

  defp next_turn(state), do: state

  defp activate_all_batteries(state, :enemy) do
    batteries =
      state.enemy.hand
      |> Enum.filter(&(&1.type == :battery))
      |> Enum.filter(&(&1.damage != :destroyed))
      |> Enum.filter(&(&1.properties.remaining_activations > 0))

    Enum.reduce(batteries, state, fn battery, acc_state ->
      dice = Dice.roll(battery.properties.dice_count, battery.properties.die_sides)
      dice_str = Enum.map_join(dice, ", ", fn d -> "#{d.value}" end)

      updated_battery = %{
        battery
        | properties: %{
            battery.properties
            | remaining_activations: battery.properties.remaining_activations - 1
          }
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
      |> Enum.filter(&(&1.type == :weapon and &1.damage != :destroyed))

    armor_cards =
      enemy.hand
      |> Enum.filter(&(&1.type == :armor and &1.damage != :destroyed))

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

  defp damage_type_label(:kinetic), do: "kinetic"
  defp damage_type_label(:energy), do: "energy"
  defp damage_type_label(:plasma), do: "plasma"
  defp damage_type_label(other), do: to_string(other)

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
