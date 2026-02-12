defmodule Botgrade.Game.CardActivation do
  @moduledoc """
  Handles immediate card activation during the power_up phase.

  When a player allocates dice to fill all slots on a card (weapon, armor, utility),
  the card is immediately activated and its effects are applied. This module handles
  the activation logic for each card type.
  """

  alias Botgrade.Game.{CombatState, Card, Damage, Targeting, WeaponResolution, ElementLogic}

  @doc """
  Activates a card immediately based on its type.

  Routes to the appropriate activation function:
  - Weapons: Deal damage or provide defense (dual-mode)
  - Armor: Add shield or plating
  - Utility: Special abilities (beam split, overcharge)

  Returns the updated combat state.
  """
  @spec activate_card(CombatState.t(), Card.t(), :player | :enemy) :: CombatState.t()
  def activate_card(state, card, who) do
    case card.type do
      :weapon -> activate_weapon(state, card, who)
      :armor -> activate_armor(state, card, who)
      :utility -> activate_utility(state, card, who)
      _ -> state
    end
  end

  @doc """
  Activates a weapon card.

  If the weapon has dual-mode and all dice meet the condition, activates as armor.
  Otherwise, activates as a damage-dealing weapon.

  Returns the updated combat state.
  """
  @spec activate_weapon(CombatState.t(), Card.t(), :player | :enemy) :: CombatState.t()
  def activate_weapon(state, weapon, who) do
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

  @doc """
  Activates an armor card.

  Adds shield or plating to the combatant based on dice values and armor type.

  Returns the updated combat state.
  """
  @spec activate_armor(CombatState.t(), Card.t(), :player | :enemy) :: CombatState.t()
  def activate_armor(state, armor, who) do
    {combatant, _defender} = get_combatants(state, who)
    who_name = if who == :player, do: "You", else: "Enemy"

    shield_base = armor.properties.shield_base + Map.get(armor.properties, :shield_base_bonus, 0)

    raw_value =
      armor.dice_slots
      |> Enum.filter(&(&1.assigned_die != nil))
      |> Enum.reduce(shield_base, fn slot, acc ->
        acc + slot.assigned_die.value
      end)

    value = WeaponResolution.apply_damage_penalty(raw_value, armor)

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

  @doc """
  Activates a utility card.

  Supported abilities:
  - :beam_split - Splits a die into two smaller dice
  - :overcharge - Adds +1 damage to all weapons this turn

  Returns the updated combat state.
  """
  @spec activate_utility(CombatState.t(), Card.t(), :player | :enemy) :: CombatState.t()
  def activate_utility(state, utility_card, who) do
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

          {state, combatant,
           "#{who_name} activates #{utility_card.name}: Split [#{die.value}] into [#{half_a}] and [#{half_b}]."}

        :overcharge ->
          state = %{state | overcharge_bonus: state.overcharge_bonus + 1}

          {state, combatant,
           "#{who_name} activates #{utility_card.name}: Spent [#{die.value}] for +1 weapon damage this turn!"}

        :quantum_tumbler ->
          new_value = :rand.uniform(die.sides)
          rerolled_die = %{sides: die.sides, value: new_value}
          combatant = %{combatant | available_dice: combatant.available_dice ++ [rerolled_die]}

          {state, combatant,
           "#{who_name} activates #{utility_card.name}: Rerolled [#{die.value}] → [#{new_value}]."}

        :internal_servo ->
          draw_count = die.value + 1
          {drawn, combatant} = draw_cards_for_servo(combatant, draw_count)

          {state, combatant,
           "#{who_name} activates #{utility_card.name}: Spent [#{die.value}] to draw #{length(drawn)} cards."}
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

  # --- Private Helpers ---

  defp activate_weapon_as_damage(state, weapon, who) do
    {attacker, defender} = get_combatants(state, who)
    who_name = if who == :player, do: "You", else: "Enemy"

    raw_damage = WeaponResolution.calculate_weapon_damage(weapon, state)
    total_damage = WeaponResolution.apply_damage_penalty(raw_damage, weapon)

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
          target_hp_before = target.current_hp

          {defender, updated_target, card_dmg, absorb_msg, state} =
            if state.target_lock_active do
              new_hp = max(0, target.current_hp - total_damage)
              updated = %{target | current_hp: new_hp} |> Card.sync_damage_state()

              {defender, updated, total_damage, " (TARGET LOCK - defenses bypassed)",
               %{state | target_lock_active: false}}
            else
              {d, t, c, a, _overkill} = Damage.apply_typed_damage(defender, target, total_damage, damage_type)
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

          # Overkill splash: if damage >= 2x target's HP, excess splashes to another target
          {defender, splash_logs} =
            if card_dmg >= 2 * target_hp_before and target_hp_before > 0 do
              splash = card_dmg - target_hp_before - 1
              targeting_profile = Map.get(weapon.properties, :targeting_profile)
              Damage.resolve_splash_chain(defender, splash, targeting_profile, 1)
            else
              {defender, []}
            end

          state = put_combatants(state, who, attacker, defender)

          state = %{
            state
            | last_attack_result: %{weapon: weapon.name, target: target.id, damage: card_dmg}
          }

          splash_log = Enum.join(splash_logs, " ")
          full_log = if splash_log != "", do: log_msg <> " " <> splash_log, else: log_msg

          {state, attacker, full_log}
      end

    # Apply element status to defender
    state = ElementLogic.apply_element_status(state, weapon, who)

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

    value = WeaponResolution.apply_damage_penalty(raw_value, weapon)

    penalty_msg =
      if weapon.damage == :damaged and raw_value != value,
        do: " (halved from #{raw_value} - damaged)",
        else: ""

    armor_type = dual_mode.armor_type

    {combatant, log_msg} =
      case armor_type do
        :plating ->
          combatant = %{combatant | plating: combatant.plating + value}

          {combatant,
           "#{who_name} activates #{weapon.name} (defense mode): +#{value} plating#{penalty_msg}."}

        :shield ->
          combatant = %{combatant | shield: combatant.shield + value}

          {combatant,
           "#{who_name} activates #{weapon.name} (defense mode): +#{value} shield#{penalty_msg}."}
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

  defp draw_cards_for_servo(robot, count) do
    {deck, discard} =
      if length(robot.deck) < count and length(robot.discard) > 0 do
        {Botgrade.Game.Deck.shuffle_discard_into_deck(robot.deck, robot.discard), []}
      else
        {robot.deck, robot.discard}
      end

    {drawn, remaining} = Botgrade.Game.Deck.draw(deck, count)
    robot = %{robot | deck: remaining, discard: discard, hand: robot.hand ++ drawn}
    {drawn, robot}
  end

  defp add_log(state, message) do
    %{state | log: [message | state.log]}
  end
end
