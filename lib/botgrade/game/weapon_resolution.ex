defmodule Botgrade.Game.WeaponResolution do
  @moduledoc """
  Handles batch weapon and armor resolution for combat.

  This module is primarily used during the enemy turn to resolve all weapons and armor
  at once, as opposed to immediate activation during the player's power_up phase.
  """

  alias Botgrade.Game.{CombatState, Card, Damage, Targeting}

  @doc """
  Resolves all weapons with dice assigned for a combatant.

  Processes each weapon in the hand, dealing damage or providing defense (dual-mode).
  Updates weapon activations counter and handles target lock state.

  Returns the updated combat state.
  """
  @spec resolve_weapons(CombatState.t(), :player | :enemy) :: CombatState.t()
  def resolve_weapons(state, who) do
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
      Enum.reduce(weapons, {attacker, defender, [], target_lock, state}, fn weapon,
                                                                              {att_acc, def_acc,
                                                                               logs, tl, st} ->
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

                {att_acc,
                 "#{who_name} activates #{weapon.name} (defense mode): +#{value} plating#{penalty_msg}."}

              :shield ->
                att_acc = %{att_acc | shield: att_acc.shield + value}

                {att_acc,
                 "#{who_name} activates #{weapon.name} (defense mode): +#{value} shield#{penalty_msg}."}
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
              {att_acc, def_acc, logs ++ ["#{who_name} fires #{weapon.name} but finds no target!"],
               tl, st}

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

  @doc """
  Resolves all armor cards with dice assigned for a combatant.

  Processes each armor card in the hand, adding shield or plating.

  Returns the updated combat state.
  """
  @spec resolve_armor(CombatState.t(), :player | :enemy) :: CombatState.t()
  def resolve_armor(state, who) do
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

  @doc """
  Resolves armor with events for animation timing.

  Returns {updated_state, events} where events is a list of {state, delay_ms} tuples.
  """
  @spec resolve_armor_with_events(CombatState.t(), :player | :enemy) ::
          {CombatState.t(), [{CombatState.t(), non_neg_integer()}]}
  def resolve_armor_with_events(state, who) do
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

  @doc """
  Resolves weapons with events for animation timing.

  Returns {updated_state, events} where events is a list of {state, delay_ms} tuples.
  """
  @spec resolve_weapons_with_events(CombatState.t(), :player | :enemy) ::
          {CombatState.t(), [{CombatState.t(), non_neg_integer()}]}
  def resolve_weapons_with_events(state, who) do
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

                {att,
                 "#{who_name} activates #{weapon.name} (defense mode): +#{value} plating#{penalty_msg}."}

              :shield ->
                att = %{att | shield: att.shield + value}

                {att,
                 "#{who_name} activates #{weapon.name} (defense mode): +#{value} shield#{penalty_msg}."}
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

          acc_state = %{
            acc_state
            | weapon_activations_this_turn: acc_state.weapon_activations_this_turn + 1
          }

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

              acc_state = %{
                acc_state
                | last_attack_result: %{weapon: weapon.name, target: target.id, damage: card_dmg}
              }

              # Apply self-damage
              acc_state = apply_self_damage(acc_state, weapon, who)

              add_log(acc_state, log_msg)
          end
        end

      {acc_state, acc_events ++ [{acc_state, 800}]}
    end)
  end

  # --- Shared Helper Functions ---

  @doc """
  Calculates the total damage for a weapon based on dice and bonuses.

  Includes:
  - Base damage + dice values * multiplier
  - Overcharge bonus (from utility cards)
  - Escalating bonus (for escalating weapons)
  """
  @spec calculate_weapon_damage(Card.t(), CombatState.t() | nil) :: non_neg_integer()
  def calculate_weapon_damage(weapon, state) do
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

  @doc """
  Applies damage penalty based on card damage state.

  - Intact: full value
  - Damaged: half value (rounded down)
  - Destroyed: zero value
  """
  @spec apply_damage_penalty(non_neg_integer(), Card.t()) :: non_neg_integer()
  def apply_damage_penalty(value, %Card{damage: :intact}), do: value
  def apply_damage_penalty(value, %Card{damage: :damaged}), do: max(0, div(value, 2))
  def apply_damage_penalty(_value, %Card{damage: :destroyed}), do: 0

  # --- Private Helpers ---

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

  defp update_card_in_zones(robot, card_id, updated_card) do
    %{
      robot
      | installed: replace_card(robot.installed, card_id, updated_card),
        hand: replace_card(robot.hand, card_id, updated_card)
    }
  end

  defp find_card_in_hand(robot, card_id) do
    Enum.find(robot.hand, &(&1.id == card_id))
  end

  defp replace_card(cards, card_id, updated_card) do
    Enum.map(cards, fn
      %Card{id: ^card_id} -> updated_card
      card -> card
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

  defp set_combatant(state, :player, combatant), do: %{state | player: combatant}
  defp set_combatant(state, :enemy, combatant), do: %{state | enemy: combatant}

  defp add_log(state, message) do
    %{state | log: [message | state.log]}
  end
end
