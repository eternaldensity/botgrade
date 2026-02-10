defmodule Botgrade.Game.CombatLogic do
  alias Botgrade.Game.{CombatState, Robot, Card, Dice, Deck, ScavengeLogic, Targeting, Damage}

  @draw_count 5
  @enemy_draw_count 4

  # --- Initialization ---

  @spec new_combat(String.t(), [Card.t()], [Card.t()], map()) :: CombatState.t()
  def new_combat(combat_id, player_cards, enemy_cards, player_resources \\ %{}) do
    player = Robot.new("player", "Player", player_cards)

    %CombatState{
      id: combat_id,
      player: %{player | resources: player_resources},
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

  # --- CPU Ability ---

  @spec activate_cpu(CombatState.t(), String.t()) :: {:ok, CombatState.t()} | {:error, String.t()}
  def activate_cpu(%CombatState{phase: :power_up, cpu_targeting: nil} = state, card_id) do
    case find_installed_card(state.player, card_id) do
      nil ->
        {:error, "CPU not found in installed components."}

      %Card{type: :cpu} = card ->
        cond do
          card.damage == :destroyed ->
            {:error, "CPU is destroyed."}

          card_fully_activated?(card) ->
            {:error, "CPU already activated this turn."}

          not cpu_has_power?(state.player, card) ->
            {:error, "Not enough batteries to power this CPU."}

          true ->
            activate_cpu_by_type(state, card)
        end

      _other ->
        {:error, "That card is not a CPU."}
    end
  end

  def activate_cpu(%CombatState{cpu_targeting: targeting}, _card_id) when not is_nil(targeting),
    do: {:error, "Already in CPU targeting mode."}

  def activate_cpu(_state, _card_id), do: {:error, "Not in power up phase."}

  defp activate_cpu_by_type(state, card) do
    if card.damage == :damaged and :rand.uniform(3) == 1 do
      combatant = mark_cpu_activated(state.player, card)
      state = %{state | player: combatant}
      state = add_log(state, "#{card.name} malfunctions! Ability failed (damaged).")
      {:ok, state}
    else
      do_activate_cpu_by_type(state, card)
    end
  end

  defp do_activate_cpu_by_type(state, card) do
    ability = card.properties.cpu_ability

    case ability.type do
      :discard_draw ->
        if not has_enough_hand_cards?(state.player, ability) do
          {:error, "Not enough cards in hand to use this ability."}
        else
          {:ok, %{state | cpu_targeting: card.id, cpu_discard_selected: [], cpu_targeting_mode: :select_hand_cards}}
        end

      :reflex_block ->
        if not has_valid_armor_target?(state.player) do
          {:error, "No armor cards in hand to boost."}
        else
          {:ok, %{state | cpu_targeting: card.id, cpu_targeting_mode: :select_installed_card, cpu_selected_installed: nil}}
        end

      :target_lock ->
        if not meets_ability_requirements?(state.player, ability) do
          {:error, "Requires #{ability.requires_card_name} in hand."}
        else
          state = execute_cpu_ability(state, card, ability, :player, nil)
          {:ok, state}
        end

      :overclock_battery ->
        if not has_valid_overclock_target?(state.player) do
          {:error, "No batteries with remaining activations."}
        else
          state = execute_cpu_ability(state, card, ability, :player, nil)
          {:ok, state}
        end

      :siphon_power ->
        cond do
          state.player.shield < 2 ->
            {:error, "Need at least 2 shield to use Siphon Power."}

          not has_valid_siphon_target?(state.player) ->
            {:error, "No batteries with depleted activations to restore."}

          true ->
            {:ok, %{state | cpu_targeting: card.id, cpu_targeting_mode: :select_installed_card, cpu_selected_installed: nil}}
        end

      :extra_activation ->
        if not has_valid_extra_activation_target?(state.player) do
          {:error, "No activated cards to reactivate."}
        else
          {:ok, %{state | cpu_targeting: card.id, cpu_targeting_mode: :select_installed_card, cpu_selected_installed: nil}}
        end
    end
  end

  defp cpu_has_power?(robot, cpu_card) do
    all_cards = robot.deck ++ robot.hand ++ robot.discard ++ robot.installed

    battery_count =
      Enum.count(all_cards, fn card ->
        card.type == :battery and card.damage != :destroyed
      end)

    cpu_slots = ceil(battery_count / 2)

    powered_cpus =
      robot.installed
      |> Enum.filter(fn card -> card.type == :cpu and card.damage != :destroyed end)
      |> Enum.take(cpu_slots)

    Enum.any?(powered_cpus, &(&1.id == cpu_card.id))
  end

  defp meets_ability_requirements?(robot, %{requires_card_name: name}) do
    Enum.any?(robot.hand, fn card ->
      card.name == name and card.damage != :destroyed
    end)
  end

  defp meets_ability_requirements?(_robot, _ability), do: true

  defp has_valid_armor_target?(robot) do
    Enum.any?(robot.hand, fn card ->
      card.type == :armor and card.damage != :destroyed
    end)
  end

  defp has_valid_overclock_target?(robot) do
    Enum.any?(robot.hand, fn card ->
      card.type == :battery and card.damage != :destroyed and
        card.properties.remaining_activations > 0
    end)
  end

  defp has_valid_siphon_target?(robot) do
    Enum.any?(robot.hand, fn card ->
      card.type == :battery and card.damage != :destroyed and
        card.properties.remaining_activations < card.properties.max_activations
    end)
  end

  defp has_valid_extra_activation_target?(robot) do
    Enum.any?(robot.hand, fn card ->
      card.type in [:weapon, :armor, :utility] and card.damage != :destroyed and
        Map.get(card.properties, :activated_this_turn, false)
    end)
  end

  @spec toggle_cpu_discard(CombatState.t(), String.t()) :: {:ok, CombatState.t()} | {:error, String.t()}
  def toggle_cpu_discard(%CombatState{phase: :power_up, cpu_targeting: cpu_id} = state, card_id)
      when not is_nil(cpu_id) do
    cpu_card = find_installed_card(state.player, cpu_id)
    max_select = cpu_card.properties.cpu_ability.discard_count

    cond do
      card_id in state.cpu_discard_selected ->
        {:ok, %{state | cpu_discard_selected: List.delete(state.cpu_discard_selected, card_id)}}

      length(state.cpu_discard_selected) >= max_select ->
        {:error, "Already selected #{max_select} cards."}

      find_card_in_hand(state.player, card_id) != nil ->
        card = find_card_in_hand(state.player, card_id)

        if card_used_this_turn?(card) do
          {:error, "Cannot discard a card that was used this turn."}
        else
          {:ok, %{state | cpu_discard_selected: state.cpu_discard_selected ++ [card_id]}}
        end

      true ->
        {:error, "Card not found in hand."}
    end
  end

  def toggle_cpu_discard(_state, _card_id), do: {:error, "Not in CPU targeting mode."}

  @spec select_cpu_target_card(CombatState.t(), String.t()) :: {:ok, CombatState.t()} | {:error, String.t()}
  def select_cpu_target_card(
        %CombatState{phase: :power_up, cpu_targeting: cpu_id, cpu_targeting_mode: :select_installed_card} = state,
        card_id
      )
      when not is_nil(cpu_id) do
    cpu_card = find_installed_card(state.player, cpu_id)
    ability = cpu_card.properties.cpu_ability
    target_card = find_card_in_hand(state.player, card_id)

    cond do
      target_card == nil ->
        {:error, "Card not found in hand."}

      not valid_cpu_target?(target_card, ability) ->
        {:error, "Invalid target for this ability."}

      state.cpu_selected_installed == card_id ->
        {:ok, %{state | cpu_selected_installed: nil}}

      true ->
        {:ok, %{state | cpu_selected_installed: card_id}}
    end
  end

  def select_cpu_target_card(_state, _card_id), do: {:error, "Not in CPU targeting mode."}

  defp valid_cpu_target?(card, %{type: :reflex_block}) do
    card.type == :armor and card.damage != :destroyed
  end

  defp valid_cpu_target?(card, %{type: :siphon_power}) do
    card.type == :battery and card.damage != :destroyed and
      card.properties.remaining_activations < card.properties.max_activations
  end

  defp valid_cpu_target?(card, %{type: :extra_activation}) do
    card.type in [:weapon, :armor, :utility] and card.damage != :destroyed and
      Map.get(card.properties, :activated_this_turn, false)
  end

  defp valid_cpu_target?(_card, _ability), do: false

  @spec confirm_cpu_ability(CombatState.t()) :: {:ok, CombatState.t()} | {:error, String.t()}
  def confirm_cpu_ability(%CombatState{phase: :power_up, cpu_targeting: cpu_id} = state)
      when not is_nil(cpu_id) do
    cpu_card = find_installed_card(state.player, cpu_id)
    ability = cpu_card.properties.cpu_ability

    case ability.type do
      :discard_draw ->
        if length(state.cpu_discard_selected) != ability.discard_count do
          {:error, "Select exactly #{ability.discard_count} cards to discard."}
        else
          {:ok, execute_cpu_ability(state, cpu_card, ability, :player, state.cpu_discard_selected)}
        end

      :reflex_block ->
        if is_nil(state.cpu_selected_installed) do
          {:error, "Select an armor card to boost."}
        else
          {:ok, execute_cpu_ability(state, cpu_card, ability, :player, state.cpu_selected_installed)}
        end

      :siphon_power ->
        cond do
          is_nil(state.cpu_selected_installed) ->
            {:error, "Select a battery to restore."}

          state.player.shield < 2 ->
            {:error, "Need at least 2 shield."}

          true ->
            {:ok, execute_cpu_ability(state, cpu_card, ability, :player, state.cpu_selected_installed)}
        end

      :extra_activation ->
        if is_nil(state.cpu_selected_installed) do
          {:error, "Select a card to reactivate."}
        else
          {:ok, execute_cpu_ability(state, cpu_card, ability, :player, state.cpu_selected_installed)}
        end
    end
  end

  def confirm_cpu_ability(_state), do: {:error, "Not in CPU targeting mode."}

  @spec cancel_cpu_ability(CombatState.t()) :: {:ok, CombatState.t()} | {:error, String.t()}
  def cancel_cpu_ability(%CombatState{phase: :power_up, cpu_targeting: cpu_id} = state)
      when not is_nil(cpu_id) do
    {:ok, clear_cpu_targeting_state(state)}
  end

  def cancel_cpu_ability(_state), do: {:error, "Not in CPU targeting mode."}

  # --- Dice Allocation (available during :power_up, with immediate activation) ---

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
          hand: replace_card(player.hand, card_id, updated_card)
      }

      state = %{state | player: player}

      # Immediate activation: when all slots filled on a weapon/armor/utility, fire it now
      if all_slots_filled?(updated_card) and updated_card.type in [:weapon, :armor, :utility] do
        state =
          state
          |> activate_card(updated_card, :player)
          |> check_victory()

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

  # --- End Turn ---

  @spec end_turn(CombatState.t()) :: CombatState.t()
  def end_turn(%CombatState{phase: :power_up} = state) do
    state
    |> clear_cpu_targeting_state()
    |> Map.put(:target_lock_active, false)
    |> Map.put(:overclock_active, false)
    |> cleanup_turn(:player)
    |> check_victory()
    |> maybe_transition_to_enemy()
  end

  # Victory was already determined mid-turn (e.g. from card activation)
  def end_turn(%CombatState{result: result} = state) when result != :ongoing, do: state

  defp maybe_transition_to_enemy(%CombatState{result: :ongoing} = state) do
    %{state | phase: :enemy_turn}
  end

  defp maybe_transition_to_enemy(state), do: state

  # --- Enemy Turn ---

  @spec enemy_turn(CombatState.t()) :: CombatState.t()
  def enemy_turn(%CombatState{phase: :enemy_turn} = state) do
    enemy = draw_cards(state.enemy, @enemy_draw_count)
    state = %{state | enemy: enemy} |> add_log("Enemy draws #{length(enemy.hand)} cards.")

    state = ai_use_cpu_ability(state, :pre_battery)
    state = activate_all_batteries(state, :enemy)
    state = ai_use_cpu_ability(state, :post_battery)
    state = ai_allocate_dice(state)

    state
    |> resolve_armor(:enemy)
    |> resolve_weapons(:enemy)
    |> cleanup_turn(:enemy)
    |> check_victory()
    |> next_turn()
  end

  # --- Enemy Turn (with events for animation) ---

  @spec enemy_turn_with_events(CombatState.t()) :: {CombatState.t(), [{CombatState.t(), non_neg_integer()}]}
  def enemy_turn_with_events(%CombatState{phase: :enemy_turn} = state) do
    events = []

    # Draw phase
    enemy = draw_cards(state.enemy, @enemy_draw_count)
    state = %{state | enemy: enemy} |> add_log("Enemy draws #{length(enemy.hand)} cards.")
    events = events ++ [{state, 400}]

    # CPU pre-battery abilities (one event per activation)
    {state, cpu_events} = ai_use_cpu_ability_with_events(state, :pre_battery, 600)
    events = events ++ cpu_events

    # Battery activations (one event per battery)
    {state, bat_events} = activate_all_batteries_with_events(state)
    events = events ++ bat_events

    # CPU post-battery abilities
    {state, cpu_events} = ai_use_cpu_ability_with_events(state, :post_battery, 600)
    events = events ++ cpu_events

    # Dice allocation: utilities first, then weapons/armor
    state = ai_allocate_dice(state)
    events = events ++ [{state, 400}]

    # Armor resolution (one event per armor)
    {state, armor_events} = resolve_armor_with_events(state, :enemy)
    events = events ++ armor_events

    # Weapon resolution (one event per weapon hit)
    {state, weapon_events} = resolve_weapons_with_events(state, :enemy)
    events = events ++ weapon_events

    # Cleanup + check victory + next turn
    state = state |> cleanup_turn(:enemy) |> check_victory() |> next_turn()
    events = events ++ [{state, 0}]

    {state, events}
  end

  defp activate_all_batteries_with_events(state) do
    batteries =
      state.enemy.hand
      |> Enum.filter(&(&1.type == :battery))
      |> Enum.filter(&(&1.damage != :destroyed))
      |> Enum.filter(&(&1.properties.remaining_activations > 0))

    {state, events} =
      Enum.reduce(batteries, {state, []}, fn battery, {acc_state, acc_events} ->
        acc_state = activate_enemy_battery(acc_state, battery)
        {acc_state, acc_events ++ [{acc_state, 500}]}
      end)

    # Overclock
    if state.overclock_active do
      overclock_target =
        state.enemy.hand
        |> Enum.find(fn card ->
          card.type == :battery and card.damage != :destroyed and
            card.properties.remaining_activations > 0
        end)

      if overclock_target do
        state =
          state
          |> add_log("Overclock: #{overclock_target.name} activates again!")
          |> activate_enemy_battery(overclock_target)
          |> Map.put(:overclock_active, false)

        {state, events ++ [{state, 500}]}
      else
        {%{state | overclock_active: false}, events}
      end
    else
      {state, events}
    end
  end

  defp ai_use_cpu_ability_with_events(state, phase, delay) do
    cpus =
      state.enemy.installed
      |> Enum.filter(fn card ->
        card.type == :cpu and
          card.damage != :destroyed and
          not card_fully_activated?(card) and
          Map.has_key?(card.properties, :cpu_ability)
      end)
      |> Enum.filter(&cpu_has_power?(state.enemy, &1))

    pre_battery = [:overclock_battery]

    cpus =
      case phase do
        :pre_battery -> Enum.filter(cpus, &(&1.properties.cpu_ability.type in pre_battery))
        :post_battery -> Enum.reject(cpus, &(&1.properties.cpu_ability.type in pre_battery))
      end

    Enum.reduce(cpus, {state, []}, fn cpu_card, {acc_state, acc_events} ->
      acc_state =
        if cpu_card.damage == :damaged and :rand.uniform(3) == 1 do
          combatant = mark_cpu_activated(acc_state.enemy, cpu_card)
          acc_state = %{acc_state | enemy: combatant}
          add_log(acc_state, "Enemy #{cpu_card.name} malfunctions! Ability failed (damaged).")
        else
          ai_execute_cpu_ability(acc_state, cpu_card, cpu_card.properties.cpu_ability)
        end

      {acc_state, acc_events ++ [{acc_state, delay}]}
    end)
  end

  defp resolve_armor_with_events(state, who) do
    {combatant, _defender} = get_combatants(state, who)
    who_name = if who == :player, do: "You", else: "Enemy"

    armor_cards =
      combatant.hand
      |> Enum.filter(&(&1.type == :armor))
      |> Enum.filter(fn card ->
        card.damage != :destroyed and
          Enum.any?(card.dice_slots, fn slot -> slot.assigned_die != nil end)
      end)

    Enum.reduce(armor_cards, {state, []}, fn armor, {acc_state, acc_events} ->
      {comb, _} = get_combatants(acc_state, who)

      shield_base = armor.properties.shield_base + Map.get(armor.properties, :shield_base_bonus, 0)

      raw_value =
        armor.dice_slots
        |> Enum.filter(&(&1.assigned_die != nil))
        |> Enum.reduce(shield_base, fn slot, acc -> acc + slot.assigned_die.value end)

      value = apply_damage_penalty(raw_value, armor)

      penalty_msg =
        if armor.damage == :damaged and raw_value != value,
          do: " (halved from #{raw_value} - damaged)",
          else: ""

      {comb, log_msg} =
        case armor.properties.armor_type do
          :plating ->
            comb = %{comb | plating: comb.plating + value}
            {comb, "#{who_name} activates #{armor.name}: +#{value} plating#{penalty_msg}."}

          :shield ->
            comb = %{comb | shield: comb.shield + value}
            {comb, "#{who_name} activates #{armor.name}: +#{value} shield#{penalty_msg}."}
        end

      acc_state =
        if who == :player,
          do: %{acc_state | player: comb},
          else: %{acc_state | enemy: comb}

      acc_state = add_log(acc_state, log_msg)
      {acc_state, acc_events ++ [{acc_state, 500}]}
    end)
  end

  defp resolve_weapons_with_events(state, who) do
    {attacker, _defender} = get_combatants(state, who)
    who_name = if who == :player, do: "You", else: "Enemy"

    weapons =
      attacker.hand
      |> Enum.filter(&(&1.type == :weapon))
      |> Enum.filter(fn card ->
        card.damage != :destroyed and
          Enum.any?(card.dice_slots, fn slot -> slot.assigned_die != nil end)
      end)

    Enum.reduce(weapons, {state, []}, fn weapon, {acc_state, acc_events} ->
      {att, def_r} = get_combatants(acc_state, who)
      dual_mode = Map.get(weapon.properties, :dual_mode)

      dice_values =
        weapon.dice_slots
        |> Enum.filter(&(&1.assigned_die != nil))
        |> Enum.map(& &1.assigned_die.value)

      acc_state =
        if dual_mode && Enum.all?(dice_values, &Card.meets_condition?(dual_mode.condition, &1)) do
          raw_value = Enum.reduce(dice_values, dual_mode.shield_base, &(&1 + &2))
          value = apply_damage_penalty(raw_value, weapon)

          penalty_msg =
            if weapon.damage == :damaged and raw_value != value,
              do: " (halved from #{raw_value} - damaged)",
              else: ""

          {att, log_msg} =
            case dual_mode.armor_type do
              :plating ->
                att = %{att | plating: att.plating + value}
                {att, "#{who_name} activates #{weapon.name} (defense mode): +#{value} plating#{penalty_msg}."}

              :shield ->
                att = %{att | shield: att.shield + value}
                {att, "#{who_name} activates #{weapon.name} (defense mode): +#{value} shield#{penalty_msg}."}
            end

          acc_state = put_combatants(acc_state, who, att, def_r)
          add_log(acc_state, log_msg)
        else
          raw_damage = calculate_weapon_damage(weapon, acc_state)
          total_damage = apply_damage_penalty(raw_damage, weapon)

          penalty_msg =
            if weapon.damage == :damaged and raw_damage != total_damage,
              do: " (halved from #{raw_damage} - damaged)",
              else: ""

          targeting_profile = Map.get(weapon.properties, :targeting_profile)
          targetable = Targeting.targetable_cards(def_r)

          acc_state = %{acc_state | weapon_activations_this_turn: acc_state.weapon_activations_this_turn + 1}

          case Targeting.select_target(targeting_profile, targetable) do
            nil ->
              add_log(acc_state, "#{who_name} fires #{weapon.name} but finds no target!")

            target ->
              damage_type = weapon.properties.damage_type
              tl = acc_state.target_lock_active

              {def_r, updated_target, card_dmg, absorb_msg, tl} =
                if tl do
                  new_hp = max(0, target.current_hp - total_damage)
                  updated = %{target | current_hp: new_hp} |> Card.sync_damage_state()
                  {def_r, updated, total_damage, " (TARGET LOCK - defenses bypassed)", false}
                else
                  {d, t, c, a} = Damage.apply_typed_damage(def_r, target, total_damage, damage_type)
                  {d, t, c, a, tl}
                end

              def_r = update_card_in_zones(def_r, target.id, updated_target)

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

              acc_state = put_combatants(acc_state, who, att, def_r)
              acc_state = %{acc_state | target_lock_active: tl}
              acc_state = %{acc_state | last_attack_result: %{weapon: weapon.name, target: target.id, damage: card_dmg}}

              # Apply self-damage
              acc_state = apply_self_damage(acc_state, weapon, who)

              add_log(acc_state, log_msg)
          end
        end

      {acc_state, acc_events ++ [{acc_state, 800}]}
    end)
  end

  # --- Immediate Card Activation (for player during :power_up) ---

  defp activate_card(state, card, who) do
    case card.type do
      :weapon -> activate_weapon(state, card, who)
      :armor -> activate_armor(state, card, who)
      :utility -> activate_utility(state, card, who)
      _ -> state
    end
  end

  defp activate_weapon(state, weapon, who) do
    dual_mode = Map.get(weapon.properties, :dual_mode)

    dice_values =
      weapon.dice_slots
      |> Enum.filter(&(&1.assigned_die != nil))
      |> Enum.map(& &1.assigned_die.value)

    if dual_mode && Enum.all?(dice_values, &Card.meets_condition?(dual_mode.condition, &1)) do
      activate_weapon_as_armor(state, weapon, who, dual_mode)
    else
      activate_weapon_as_damage(state, weapon, who)
    end
  end

  defp activate_weapon_as_damage(state, weapon, who) do
    {attacker, defender} = get_combatants(state, who)
    who_name = if who == :player, do: "You", else: "Enemy"

    raw_damage = calculate_weapon_damage(weapon, state)
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

          {defender, updated_target, card_dmg, absorb_msg, state} =
            if state.target_lock_active do
              new_hp = max(0, target.current_hp - total_damage)
              updated = %{target | current_hp: new_hp} |> Card.sync_damage_state()
              {defender, updated, total_damage, " (TARGET LOCK - defenses bypassed)", %{state | target_lock_active: false}}
            else
              {d, t, c, a} = Damage.apply_typed_damage(defender, target, total_damage, damage_type)
              {d, t, c, a, state}
            end

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

    # Track weapon activations for escalating weapons
    state = %{state | weapon_activations_this_turn: state.weapon_activations_this_turn + 1}

    # Store result on card, clear slots, mark activated
    dice_used = Enum.map(weapon.dice_slots, & &1.assigned_die) |> Enum.reject(&is_nil/1)

    result_card =
      weapon
      |> clear_card_slots()
      |> Map.put(:last_result, %{type: :damage, value: total_damage, dice: dice_used})

    attacker = mark_card_activated_in_hand(attacker, weapon.id, result_card)

    state =
      if who == :player,
        do: %{state | player: attacker},
        else: %{state | enemy: attacker}

    # Self-damage: weapon hurts itself after firing
    state = apply_self_damage(state, weapon, who)

    add_log(state, log_msg)
  end

  defp activate_weapon_as_armor(state, weapon, who, dual_mode) do
    {combatant, _defender} = get_combatants(state, who)
    who_name = if who == :player, do: "You", else: "Enemy"

    raw_value =
      weapon.dice_slots
      |> Enum.filter(&(&1.assigned_die != nil))
      |> Enum.reduce(dual_mode.shield_base, fn slot, acc ->
        acc + slot.assigned_die.value
      end)

    value = apply_damage_penalty(raw_value, weapon)

    penalty_msg =
      if weapon.damage == :damaged and raw_value != value,
        do: " (halved from #{raw_value} - damaged)",
        else: ""

    armor_type = dual_mode.armor_type

    {combatant, log_msg} =
      case armor_type do
        :plating ->
          combatant = %{combatant | plating: combatant.plating + value}
          {combatant, "#{who_name} activates #{weapon.name} (defense mode): +#{value} plating#{penalty_msg}."}

        :shield ->
          combatant = %{combatant | shield: combatant.shield + value}
          {combatant, "#{who_name} activates #{weapon.name} (defense mode): +#{value} shield#{penalty_msg}."}
      end

    dice_used = Enum.map(weapon.dice_slots, & &1.assigned_die) |> Enum.reject(&is_nil/1)

    result_card =
      weapon
      |> clear_card_slots()
      |> Map.put(:last_result, %{type: armor_type, value: value, dice: dice_used})

    combatant = mark_card_activated_in_hand(combatant, weapon.id, result_card)

    state =
      if who == :player,
        do: %{state | player: combatant},
        else: %{state | enemy: combatant}

    add_log(state, log_msg)
  end

  defp activate_armor(state, armor, who) do
    {combatant, _defender} = get_combatants(state, who)
    who_name = if who == :player, do: "You", else: "Enemy"

    shield_base = armor.properties.shield_base + Map.get(armor.properties, :shield_base_bonus, 0)

    raw_value =
      armor.dice_slots
      |> Enum.filter(&(&1.assigned_die != nil))
      |> Enum.reduce(shield_base, fn slot, acc ->
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

    # Store result on card, clear slots, mark activated
    dice_used = Enum.map(armor.dice_slots, & &1.assigned_die) |> Enum.reject(&is_nil/1)
    result_type = armor.properties.armor_type

    result_card =
      armor
      |> clear_card_slots()
      |> Map.put(:last_result, %{type: result_type, value: value, dice: dice_used})

    combatant = mark_card_activated_in_hand(combatant, armor.id, result_card)

    state =
      if who == :player,
        do: %{state | player: combatant},
        else: %{state | enemy: combatant}

    add_log(state, log_msg)
  end

  defp activate_utility(state, utility_card, who) do
    {combatant, _} = get_combatants(state, who)
    who_name = if who == :player, do: "You", else: "Enemy"
    ability = utility_card.properties.utility_ability

    die = hd(Enum.filter(utility_card.dice_slots, &(&1.assigned_die != nil))).assigned_die

    {state, combatant, log_msg} =
      case ability do
        :beam_split ->
          half_a = ceil(die.value / 2)
          half_b = floor(die.value / 2)

          new_dice = [
            %{sides: die.sides, value: max(1, half_a)},
            %{sides: die.sides, value: max(1, half_b)}
          ]

          combatant = %{combatant | available_dice: combatant.available_dice ++ new_dice}
          {state, combatant, "#{who_name} activates #{utility_card.name}: Split [#{die.value}] into [#{half_a}] and [#{half_b}]."}

        :overcharge ->
          state = %{state | overcharge_bonus: state.overcharge_bonus + 1}
          {state, combatant, "#{who_name} activates #{utility_card.name}: Spent [#{die.value}] for +1 weapon damage this turn!"}
      end

    result_card =
      utility_card
      |> clear_card_slots()
      |> Map.put(:last_result, %{type: :utility, ability: ability, dice: [die]})

    combatant = mark_card_activated_in_hand(combatant, utility_card.id, result_card)

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
      attacker.hand
      |> Enum.filter(&(&1.type == :weapon))
      |> Enum.filter(fn card ->
        card.damage != :destroyed and
          Enum.any?(card.dice_slots, fn slot -> slot.assigned_die != nil end)
      end)

    target_lock = state.target_lock_active

    {attacker, defender, log_entries, target_lock, state} =
      Enum.reduce(weapons, {attacker, defender, [], target_lock, state}, fn weapon, {att_acc, def_acc, logs, tl, st} ->
        dual_mode = Map.get(weapon.properties, :dual_mode)

        dice_values =
          weapon.dice_slots
          |> Enum.filter(&(&1.assigned_die != nil))
          |> Enum.map(& &1.assigned_die.value)

        if dual_mode && Enum.all?(dice_values, &Card.meets_condition?(dual_mode.condition, &1)) do
          # Dual-mode: generate defense instead of damage
          raw_value = Enum.reduce(dice_values, dual_mode.shield_base, &(&1 + &2))
          value = apply_damage_penalty(raw_value, weapon)

          penalty_msg =
            if weapon.damage == :damaged and raw_value != value,
              do: " (halved from #{raw_value} - damaged)",
              else: ""

          {att_acc, log_msg} =
            case dual_mode.armor_type do
              :plating ->
                att_acc = %{att_acc | plating: att_acc.plating + value}
                {att_acc, "#{who_name} activates #{weapon.name} (defense mode): +#{value} plating#{penalty_msg}."}

              :shield ->
                att_acc = %{att_acc | shield: att_acc.shield + value}
                {att_acc, "#{who_name} activates #{weapon.name} (defense mode): +#{value} shield#{penalty_msg}."}
            end

          {att_acc, def_acc, logs ++ [log_msg], tl, st}
        else
          # Normal weapon damage
          raw_damage = calculate_weapon_damage(weapon, st)
          total_damage = apply_damage_penalty(raw_damage, weapon)

          penalty_msg =
            if weapon.damage == :damaged and raw_damage != total_damage,
              do: " (halved from #{raw_damage} - damaged)",
              else: ""

          targeting_profile = Map.get(weapon.properties, :targeting_profile)
          targetable = Targeting.targetable_cards(def_acc)

          st = %{st | weapon_activations_this_turn: st.weapon_activations_this_turn + 1}

          case Targeting.select_target(targeting_profile, targetable) do
            nil ->
              {att_acc, def_acc, logs ++ ["#{who_name} fires #{weapon.name} but finds no target!"], tl, st}

            target ->
              damage_type = weapon.properties.damage_type

              {def_acc, updated_target, card_dmg, absorb_msg, tl} =
                if tl do
                  new_hp = max(0, target.current_hp - total_damage)
                  updated = %{target | current_hp: new_hp} |> Card.sync_damage_state()
                  {def_acc, updated, total_damage, " (TARGET LOCK - defenses bypassed)", false}
                else
                  {d, t, c, a} = Damage.apply_typed_damage(def_acc, target, total_damage, damage_type)
                  {d, t, c, a, tl}
                end

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

              # Apply self-damage
              {att_acc, self_logs} = resolve_self_damage(att_acc, weapon)

              {att_acc, def_acc, logs ++ [log_msg] ++ self_logs, tl, st}
          end
        end
      end)

    state = put_combatants(state, who, attacker, defender)
    state = %{state | target_lock_active: target_lock}
    Enum.reduce(log_entries, state, fn msg, s -> add_log(s, msg) end)
  end

  defp resolve_armor(state, who) do
    {combatant, _defender} = get_combatants(state, who)
    who_name = if who == :player, do: "You", else: "Enemy"

    armor_cards =
      combatant.hand
      |> Enum.filter(&(&1.type == :armor))
      |> Enum.filter(fn card ->
        card.damage != :destroyed and
          Enum.any?(card.dice_slots, fn slot -> slot.assigned_die != nil end)
      end)

    {combatant, log_entries} =
      Enum.reduce(armor_cards, {combatant, []}, fn armor, {comb_acc, logs} ->
        shield_base = armor.properties.shield_base + Map.get(armor.properties, :shield_base_bonus, 0)

        raw_value =
          armor.dice_slots
          |> Enum.filter(&(&1.assigned_die != nil))
          |> Enum.reduce(shield_base, fn slot, acc ->
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

    # Clear activation flags, results, and shield_base_bonus
    all_cards =
      Enum.map(hand_cards, fn card ->
        card = %{card | last_result: nil}
        props = Map.delete(card.properties, :activated_this_turn)
        props = Map.delete(props, :activations_this_turn)

        props =
          cond do
            card.type == :armor -> Map.delete(props, :shield_base_bonus)
            true -> props
          end

        %{card | properties: props}
      end)

    # Capacitors with stored dice stay in hand for next turn
    {charged_capacitors, to_discard} =
      Enum.split_with(all_cards, fn card ->
        card.type == :capacitor and Enum.any?(card.dice_slots, &(&1.assigned_die != nil))
      end)

    # Reset CPU activation flags on installed cards
    installed = Enum.map(combatant.installed, &reset_cpu_flag/1)

    combatant = %{
      combatant
      | hand: charged_capacitors,
        discard: combatant.discard ++ to_discard,
        installed: installed,
        available_dice: [],
        # Shield resets each turn, plating persists
        shield: 0
    }

    state =
      if who == :player,
        do: %{state | player: combatant},
        else: %{state | enemy: combatant}

    # Reset per-turn state
    %{state | overcharge_bonus: 0, weapon_activations_this_turn: 0}
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
    all_cards = robot.installed ++ robot.deck ++ robot.hand ++ robot.discard

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

  defp calculate_weapon_damage(weapon, state) do
    multiplier = Map.get(weapon.properties, :damage_multiplier, 1)

    base =
      weapon.dice_slots
      |> Enum.filter(&(&1.assigned_die != nil))
      |> Enum.reduce(weapon.properties.damage_base, fn slot, acc ->
        acc + slot.assigned_die.value * multiplier
      end)

    # Add overcharge bonus
    overcharge = if state, do: state.overcharge_bonus, else: 0

    # Add escalating bonus (one per prior weapon activation this turn)
    escalating =
      if Map.get(weapon.properties, :escalating, false) and state do
        state.weapon_activations_this_turn
      else
        0
      end

    max(0, base + overcharge + escalating)
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

  defp mark_card_activated_in_hand(robot, card_id, result_card) do
    props = result_card.properties
    max_per_turn = Map.get(props, :max_activations_per_turn)

    props =
      if max_per_turn do
        count = Map.get(props, :activations_this_turn, 0) + 1
        props
        |> Map.put(:activations_this_turn, count)
        |> Map.put(:activated_this_turn, count >= max_per_turn)
      else
        Map.put(props, :activated_this_turn, true)
      end

    activated_card = %{result_card | properties: props}
    %{robot | hand: replace_card(robot.hand, card_id, activated_card)}
  end

  defp update_card_in_zones(robot, card_id, updated_card) do
    %{
      robot
      | installed: replace_card(robot.installed, card_id, updated_card),
        hand: replace_card(robot.hand, card_id, updated_card)
    }
  end

  defp clear_dice_from_cards(cards) do
    Enum.map(cards, fn card ->
      if card.type == :capacitor do
        card
      else
        updated_slots = Enum.map(card.dice_slots, &%{&1 | assigned_die: nil})
        %{card | dice_slots: updated_slots}
      end
    end)
  end

  defp reset_cpu_flag(%Card{type: :cpu} = card) do
    props = card.properties
    props = Map.delete(props, :activated_this_turn)
    props = Map.delete(props, :activations_this_turn)
    %{card | properties: props}
  end

  defp reset_cpu_flag(card), do: card

  defp card_used_this_turn?(card) do
    Map.get(card.properties, :activated_this_turn, false)
  end

  defp card_fully_activated?(card) do
    max_per_turn = Map.get(card.properties, :max_activations_per_turn)

    if max_per_turn do
      Map.get(card.properties, :activations_this_turn, 0) >= max_per_turn
    else
      Map.get(card.properties, :activated_this_turn, false)
    end
  end

  defp find_installed_card(robot, card_id) do
    Enum.find(robot.installed, &(&1.id == card_id))
  end

  defp has_enough_hand_cards?(robot, %{discard_count: n}) do
    discardable = Enum.reject(robot.hand, &card_used_this_turn?/1)
    length(discardable) >= n
  end

  defp execute_cpu_ability(state, cpu_card, %{type: :discard_draw} = ability, who, selected_ids) do
    {combatant, _} = get_combatants(state, who)
    who_name = if who == :player, do: "You", else: "Enemy"

    {discarded_cards, remaining_hand} =
      Enum.split_with(combatant.hand, fn card -> card.id in selected_ids end)

    combatant = %{combatant | hand: remaining_hand, discard: combatant.discard ++ discarded_cards}
    combatant = draw_cards(combatant, ability.draw_count)

    updated_cpu = %{cpu_card | properties: Map.put(cpu_card.properties, :activated_this_turn, true)}
    combatant = %{combatant | installed: replace_card(combatant.installed, cpu_card.id, updated_cpu)}

    discarded_names = Enum.map_join(discarded_cards, ", ", & &1.name)

    state = set_combatant(state, who, combatant)
    state = if who == :player, do: clear_cpu_targeting_state(state), else: state
    add_log(state, "#{who_name} activates #{cpu_card.name}: discarded #{discarded_names}, drew #{ability.draw_count}.")
  end

  defp execute_cpu_ability(state, cpu_card, %{type: :reflex_block}, who, target_card_id) do
    {combatant, _} = get_combatants(state, who)
    who_name = if who == :player, do: "You", else: "Enemy"

    target_card = find_card_in_hand(combatant, target_card_id)
    bonus = Map.get(target_card.properties, :shield_base_bonus, 0) + 1
    updated_target = %{target_card | properties: Map.put(target_card.properties, :shield_base_bonus, bonus)}
    combatant = %{combatant | hand: replace_card(combatant.hand, target_card_id, updated_target)}

    combatant = mark_cpu_activated(combatant, cpu_card)
    state = set_combatant(state, who, combatant)
    state = if who == :player, do: clear_cpu_targeting_state(state), else: state
    add_log(state, "#{who_name} activates #{cpu_card.name}: Reflex Block on #{target_card.name} (+1 shield base).")
  end

  defp execute_cpu_ability(state, cpu_card, %{type: :target_lock}, who, _target) do
    {combatant, _} = get_combatants(state, who)
    who_name = if who == :player, do: "You", else: "Enemy"

    combatant = mark_cpu_activated(combatant, cpu_card)
    state = set_combatant(state, who, combatant)
    state = %{state | target_lock_active: true}
    state = if who == :player, do: clear_cpu_targeting_state(state), else: state
    add_log(state, "#{who_name} activates #{cpu_card.name}: Target Lock! Next weapon bypasses defenses.")
  end

  defp execute_cpu_ability(state, cpu_card, %{type: :overclock_battery}, who, _target) do
    {combatant, _} = get_combatants(state, who)
    who_name = if who == :player, do: "You", else: "Enemy"

    combatant = mark_cpu_activated(combatant, cpu_card)
    state = set_combatant(state, who, combatant)
    state = %{state | overclock_active: true}
    state = if who == :player, do: clear_cpu_targeting_state(state), else: state
    add_log(state, "#{who_name} activates #{cpu_card.name}: Overclock! Next battery can activate twice.")
  end

  defp execute_cpu_ability(state, cpu_card, %{type: :siphon_power}, who, target_card_id) do
    {combatant, _} = get_combatants(state, who)
    who_name = if who == :player, do: "You", else: "Enemy"

    target_card = find_card_in_hand(combatant, target_card_id)
    remaining = target_card.properties.remaining_activations + 1
    updated_target = %{target_card | properties: %{target_card.properties | remaining_activations: remaining}}
    combatant = %{combatant | hand: replace_card(combatant.hand, target_card_id, updated_target)}
    combatant = %{combatant | shield: combatant.shield - 2}

    combatant = mark_cpu_activated(combatant, cpu_card)
    state = set_combatant(state, who, combatant)
    state = if who == :player, do: clear_cpu_targeting_state(state), else: state
    add_log(state, "#{who_name} activates #{cpu_card.name}: Siphoned 2 shield to restore #{target_card.name}.")
  end

  defp execute_cpu_ability(state, cpu_card, %{type: :extra_activation}, who, target_card_id) do
    {combatant, _} = get_combatants(state, who)
    who_name = if who == :player, do: "You", else: "Enemy"

    target_card = find_card_in_hand(combatant, target_card_id)

    # Reset the card's activated state so it can be used again
    props = target_card.properties
    props = Map.put(props, :activated_this_turn, false)
    props = Map.delete(props, :activations_this_turn)
    updated_target = %{target_card | properties: props}

    combatant = %{combatant | hand: replace_card(combatant.hand, target_card_id, updated_target)}

    combatant = mark_cpu_activated(combatant, cpu_card)
    state = set_combatant(state, who, combatant)
    state = if who == :player, do: clear_cpu_targeting_state(state), else: state
    add_log(state, "#{who_name} activates #{cpu_card.name}: #{target_card.name} can activate again!")
  end

  defp mark_cpu_activated(combatant, cpu_card) do
    props = cpu_card.properties
    max_per_turn = Map.get(props, :max_activations_per_turn)

    props =
      if max_per_turn do
        count = Map.get(props, :activations_this_turn, 0) + 1
        props
        |> Map.put(:activations_this_turn, count)
        |> Map.put(:activated_this_turn, count >= max_per_turn)
      else
        Map.put(props, :activated_this_turn, true)
      end

    updated_cpu = %{cpu_card | properties: props}
    %{combatant | installed: replace_card(combatant.installed, cpu_card.id, updated_cpu)}
  end

  defp set_combatant(state, :player, combatant), do: %{state | player: combatant}
  defp set_combatant(state, :enemy, combatant), do: %{state | enemy: combatant}

  defp clear_cpu_targeting_state(state) do
    %{state | cpu_targeting: nil, cpu_discard_selected: [], cpu_targeting_mode: nil, cpu_selected_installed: nil}
  end

  defp apply_battery_damage_penalty(dice, die_sides) do
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

  defp apply_damage_penalty(value, %Card{damage: :intact}), do: value
  defp apply_damage_penalty(value, %Card{damage: :damaged}), do: max(0, div(value, 2))
  defp apply_damage_penalty(_value, %Card{damage: :destroyed}), do: 0

  defp resolve_self_damage(combatant, weapon) do
    self_damage = Map.get(weapon.properties, :self_damage, 0)

    if self_damage > 0 do
      card = find_card_in_hand(combatant, weapon.id)

      if card && card.current_hp do
        new_hp = max(0, card.current_hp - self_damage)
        updated = %{card | current_hp: new_hp} |> Card.sync_damage_state()
        combatant = %{combatant | hand: replace_card(combatant.hand, weapon.id, updated)}

        msg =
          if updated.current_hp <= 0,
            do: "#{weapon.name} takes #{self_damage} self-damage. DESTROYED!",
            else: "#{weapon.name} takes #{self_damage} self-damage."

        {combatant, [msg]}
      else
        {combatant, []}
      end
    else
      {combatant, []}
    end
  end

  defp apply_self_damage(state, weapon, who) do
    self_damage = Map.get(weapon.properties, :self_damage, 0)

    if self_damage > 0 do
      {combatant, _} = get_combatants(state, who)
      card = find_card_in_hand(combatant, weapon.id)

      if card && card.current_hp do
        new_hp = max(0, card.current_hp - self_damage)
        updated = %{card | current_hp: new_hp} |> Card.sync_damage_state()
        combatant = %{combatant | hand: replace_card(combatant.hand, weapon.id, updated)}
        state = set_combatant(state, who, combatant)

        self_msg =
          if updated.current_hp <= 0,
            do: "#{weapon.name} takes #{self_damage} self-damage. DESTROYED!",
            else: "#{weapon.name} takes #{self_damage} self-damage."

        add_log(state, self_msg)
      else
        state
      end
    else
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
      |> Enum.filter(&(&1.damage != :destroyed))
      |> Enum.filter(&(&1.properties.remaining_activations > 0))

    state =
      Enum.reduce(batteries, state, fn battery, acc_state ->
        activate_enemy_battery(acc_state, battery)
      end)

    # Overclock: find a battery that can activate again and fire it
    if state.overclock_active do
      overclock_target =
        state.enemy.hand
        |> Enum.find(fn card ->
          card.type == :battery and card.damage != :destroyed and
            card.properties.remaining_activations > 0
        end)

      if overclock_target do
        state
        |> add_log("Overclock: #{overclock_target.name} activates again!")
        |> activate_enemy_battery(overclock_target)
        |> Map.put(:overclock_active, false)
      else
        %{state | overclock_active: false}
      end
    else
      state
    end
  end

  defp activate_enemy_battery(state, battery) do
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

  defp ai_allocate_dice(state) do
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

  defp ai_allocate_and_activate_utilities(state) do
    utility_cards =
      state.enemy.hand
      |> Enum.filter(&(&1.type == :utility and &1.damage != :destroyed and not card_fully_activated?(&1)))

    Enum.reduce(utility_cards, state, fn util_card, acc_state ->
      # Try to assign a die to the utility card's slot
      enemy = acc_state.enemy
      slot = hd(util_card.dice_slots)

      best_die =
        if util_card.properties.utility_ability == :overcharge do
          # For overcharge, pick the lowest valid die (3+)
          enemy.available_dice
          |> Enum.with_index()
          |> Enum.filter(fn {d, _} -> Card.meets_condition?(slot.condition, d.value) end)
          |> Enum.sort_by(fn {d, _} -> d.value end)
          |> List.first()
        else
          # For beam_split, pick the highest die to get the most value
          enemy.available_dice
          |> Enum.with_index()
          |> Enum.filter(fn {d, _} -> Card.meets_condition?(slot.condition, d.value) end)
          |> Enum.sort_by(fn {d, _} -> d.value end, :desc)
          |> List.first()
        end

      case best_die do
        nil -> acc_state
        {die, die_idx} ->
          # Assign die to slot
          updated_slot = %{slot | assigned_die: die}
          updated_card = %{util_card | dice_slots: [updated_slot]}
          enemy = %{enemy | hand: replace_card(enemy.hand, util_card.id, updated_card), available_dice: List.delete_at(enemy.available_dice, die_idx)}
          acc_state = %{acc_state | enemy: enemy}
          acc_state = add_log(acc_state, "Enemy assigns die [#{die.value}] to #{util_card.name}.")

          # Activate the utility
          activate_utility(acc_state, updated_card, :enemy)
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

  @pre_battery_abilities [:overclock_battery]

  defp ai_use_cpu_ability(state, phase) do
    cpus =
      state.enemy.installed
      |> Enum.filter(fn card ->
        card.type == :cpu and
          card.damage != :destroyed and
          not card_fully_activated?(card) and
          Map.has_key?(card.properties, :cpu_ability)
      end)
      |> Enum.filter(&cpu_has_power?(state.enemy, &1))

    cpus =
      case phase do
        :pre_battery -> Enum.filter(cpus, &(&1.properties.cpu_ability.type in @pre_battery_abilities))
        :post_battery -> Enum.reject(cpus, &(&1.properties.cpu_ability.type in @pre_battery_abilities))
      end

    Enum.reduce(cpus, state, fn cpu_card, acc_state ->
      if cpu_card.damage == :damaged and :rand.uniform(3) == 1 do
        combatant = mark_cpu_activated(acc_state.enemy, cpu_card)
        acc_state = %{acc_state | enemy: combatant}
        add_log(acc_state, "Enemy #{cpu_card.name} malfunctions! Ability failed (damaged).")
      else
        ai_execute_cpu_ability(acc_state, cpu_card, cpu_card.properties.cpu_ability)
      end
    end)
  end

  defp ai_execute_cpu_ability(state, cpu_card, %{type: :discard_draw} = ability) do
    enemy = state.enemy

    # Exclude cards used this turn from discard candidates
    discardable = Enum.reject(enemy.hand, &card_used_this_turn?/1)

    if length(discardable) >= ability.discard_count do
      # AI picks worst cards: destroyed > depleted batteries > damaged > others
      sorted_hand =
        Enum.sort_by(discardable, fn card ->
          cond do
            card.damage == :destroyed -> 0
            card.type == :battery and card.properties.remaining_activations <= 0 -> 1
            card.damage == :damaged -> 2
            true -> 3
          end
        end)

      to_discard = Enum.take(sorted_hand, ability.discard_count)
      selected_ids = Enum.map(to_discard, & &1.id)

      execute_cpu_ability(state, cpu_card, ability, :enemy, selected_ids)
    else
      state
    end
  end

  defp ai_execute_cpu_ability(state, cpu_card, %{type: :reflex_block} = ability) do
    # Pick best non-destroyed armor in hand (prioritize ones with empty dice slots)
    best_armor =
      state.enemy.hand
      |> Enum.filter(&(&1.type == :armor and &1.damage != :destroyed))
      |> Enum.sort_by(fn card ->
        empty_slots = Enum.count(card.dice_slots, &is_nil(&1.assigned_die))
        {if(empty_slots > 0, do: 0, else: 1), -card.properties.shield_base}
      end)
      |> List.first()

    if best_armor do
      execute_cpu_ability(state, cpu_card, ability, :enemy, best_armor.id)
    else
      state
    end
  end

  defp ai_execute_cpu_ability(state, cpu_card, %{type: :target_lock} = ability) do
    has_weapons =
      Enum.any?(state.enemy.hand, &(&1.type == :weapon and &1.damage != :destroyed))

    if has_weapons and meets_ability_requirements?(state.enemy, ability) do
      execute_cpu_ability(state, cpu_card, ability, :enemy, nil)
    else
      state
    end
  end

  defp ai_execute_cpu_ability(state, cpu_card, %{type: :overclock_battery} = ability) do
    has_batteries =
      Enum.any?(state.enemy.hand, fn card ->
        card.type == :battery and card.damage != :destroyed and
          card.properties.remaining_activations > 0
      end)

    if has_batteries do
      execute_cpu_ability(state, cpu_card, ability, :enemy, nil)
    else
      state
    end
  end

  defp ai_execute_cpu_ability(state, cpu_card, %{type: :siphon_power} = ability) do
    best_battery =
      state.enemy.hand
      |> Enum.filter(fn card ->
        card.type == :battery and card.damage != :destroyed and
          card.properties.remaining_activations < card.properties.max_activations
      end)
      |> Enum.sort_by(& &1.properties.remaining_activations)
      |> List.first()

    if state.enemy.shield >= 2 and best_battery do
      execute_cpu_ability(state, cpu_card, ability, :enemy, best_battery.id)
    else
      state
    end
  end

  defp ai_execute_cpu_ability(state, cpu_card, %{type: :extra_activation} = ability) do
    # AI picks the best activated weapon/armor/utility to reactivate
    best_target =
      state.enemy.hand
      |> Enum.filter(fn card ->
        card.type in [:weapon, :armor, :utility] and card.damage != :destroyed and
          Map.get(card.properties, :activated_this_turn, false)
      end)
      |> Enum.sort_by(fn card ->
        if card.type == :weapon, do: 0, else: 1
      end)
      |> List.first()

    if best_target do
      execute_cpu_ability(state, cpu_card, ability, :enemy, best_target.id)
    else
      state
    end
  end

  defp add_log(state, message) do
    %{state | log: [message | state.log]}
  end
end
