defmodule Botgrade.Game.CPULogic do
  @moduledoc """
  Handles CPU (Central Processing Unit) card abilities in combat.

  CPUs provide special abilities that can be activated during the power_up phase:
  - Discard/Draw: Discard cards to draw new ones
  - Reflex Block: Boost an armor card's shield value
  - Target Lock: Next weapon bypasses all defenses
  - Overclock Battery: Allow a battery to activate twice
  - Siphon Power: Convert shield to battery charges
  - Extra Activation: Allow a card to activate again this turn

  CPUs require power from batteries (2 batteries = 1 CPU slot).
  Damaged CPUs have a 33% chance to malfunction when activated.
  """

  alias Botgrade.Game.{CombatState, Card, Deck}

  @doc """
  Activates a CPU card during the power_up phase.

  Validates power requirements, damage state, and ability requirements before
  entering targeting mode or immediately executing the ability.

  Returns {:ok, updated_state} if successful, {:error, reason} if activation fails.
  """
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

  @doc """
  Toggles a card in the discard selection for discard_draw abilities.

  Used during CPU targeting mode to select which cards to discard.

  Returns {:ok, updated_state} with card added/removed from selection.
  """
  @spec toggle_cpu_discard(CombatState.t(), String.t()) ::
          {:ok, CombatState.t()} | {:error, String.t()}
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

  @doc """
  Selects a target card for CPU abilities that require targeting.

  Used for reflex_block, siphon_power, and extra_activation abilities.

  Returns {:ok, updated_state} with target selected or deselected.
  """
  @spec select_cpu_target_card(CombatState.t(), String.t()) ::
          {:ok, CombatState.t()} | {:error, String.t()}
  def select_cpu_target_card(
        %CombatState{
          phase: :power_up,
          cpu_targeting: cpu_id,
          cpu_targeting_mode: :select_installed_card
        } = state,
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

  @doc """
  Confirms and executes the CPU ability with selected targets.

  Validates that all required targets are selected before executing.

  Returns {:ok, updated_state} if successful, {:error, reason} if validation fails.
  """
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
          {:ok,
           execute_cpu_ability(state, cpu_card, ability, :player, state.cpu_selected_installed)}
        end

      :siphon_power ->
        cond do
          is_nil(state.cpu_selected_installed) ->
            {:error, "Select a battery to restore."}

          state.player.shield < 2 ->
            {:error, "Need at least 2 shield."}

          true ->
            {:ok,
             execute_cpu_ability(state, cpu_card, ability, :player, state.cpu_selected_installed)}
        end

      :extra_activation ->
        if is_nil(state.cpu_selected_installed) do
          {:error, "Select a card to reactivate."}
        else
          {:ok,
           execute_cpu_ability(state, cpu_card, ability, :player, state.cpu_selected_installed)}
        end
    end
  end

  def confirm_cpu_ability(_state), do: {:error, "Not in CPU targeting mode."}

  @doc """
  Cancels CPU targeting mode and returns to normal power_up phase.

  Returns {:ok, updated_state} with targeting state cleared.
  """
  @spec cancel_cpu_ability(CombatState.t()) :: {:ok, CombatState.t()} | {:error, String.t()}
  def cancel_cpu_ability(%CombatState{phase: :power_up, cpu_targeting: cpu_id} = state)
      when not is_nil(cpu_id) do
    {:ok, clear_cpu_targeting_state(state)}
  end

  def cancel_cpu_ability(_state), do: {:error, "Not in CPU targeting mode."}

  @doc """
  Executes a CPU ability for a specific combatant.

  This is the core function that applies the ability's effects.
  Used by both player (after confirmation) and AI (automatically).

  Returns the updated combat state.
  """
  @spec execute_cpu_ability(CombatState.t(), Card.t(), map(), :player | :enemy, any()) ::
          CombatState.t()
  def execute_cpu_ability(state, cpu_card, %{type: :discard_draw} = ability, who, selected_ids) do
    {combatant, _} = get_combatants(state, who)
    who_name = if who == :player, do: "You", else: "Enemy"

    {discarded_cards, remaining_hand} =
      Enum.split_with(combatant.hand, fn card -> card.id in selected_ids end)

    combatant = %{combatant | hand: remaining_hand, discard: combatant.discard ++ discarded_cards}
    combatant = draw_cards(combatant, ability.draw_count)

    updated_cpu = %{cpu_card | properties: Map.put(cpu_card.properties, :activated_this_turn, true)}

    combatant = %{
      combatant
      | installed: replace_card(combatant.installed, cpu_card.id, updated_cpu)
    }

    discarded_names = Enum.map_join(discarded_cards, ", ", & &1.name)

    state = set_combatant(state, who, combatant)
    state = if who == :player, do: clear_cpu_targeting_state(state), else: state

    add_log(
      state,
      "#{who_name} activates #{cpu_card.name}: discarded #{discarded_names}, drew #{ability.draw_count}."
    )
  end

  def execute_cpu_ability(state, cpu_card, %{type: :reflex_block}, who, target_card_id) do
    {combatant, _} = get_combatants(state, who)
    who_name = if who == :player, do: "You", else: "Enemy"

    target_card = find_card_in_hand(combatant, target_card_id)
    bonus = Map.get(target_card.properties, :shield_base_bonus, 0) + 1

    updated_target = %{
      target_card
      | properties: Map.put(target_card.properties, :shield_base_bonus, bonus)
    }

    combatant = %{combatant | hand: replace_card(combatant.hand, target_card_id, updated_target)}

    combatant = mark_cpu_activated(combatant, cpu_card)
    state = set_combatant(state, who, combatant)
    state = if who == :player, do: clear_cpu_targeting_state(state), else: state

    add_log(
      state,
      "#{who_name} activates #{cpu_card.name}: Reflex Block on #{target_card.name} (+1 shield base)."
    )
  end

  def execute_cpu_ability(state, cpu_card, %{type: :target_lock}, who, _target) do
    {combatant, _} = get_combatants(state, who)
    who_name = if who == :player, do: "You", else: "Enemy"

    combatant = mark_cpu_activated(combatant, cpu_card)
    state = set_combatant(state, who, combatant)
    state = %{state | target_lock_active: true}
    state = if who == :player, do: clear_cpu_targeting_state(state), else: state

    add_log(
      state,
      "#{who_name} activates #{cpu_card.name}: Target Lock! Next weapon bypasses defenses."
    )
  end

  def execute_cpu_ability(state, cpu_card, %{type: :overclock_battery}, who, _target) do
    {combatant, _} = get_combatants(state, who)
    who_name = if who == :player, do: "You", else: "Enemy"

    combatant = mark_cpu_activated(combatant, cpu_card)
    state = set_combatant(state, who, combatant)
    state = %{state | overclock_active: true}
    state = if who == :player, do: clear_cpu_targeting_state(state), else: state

    add_log(
      state,
      "#{who_name} activates #{cpu_card.name}: Overclock! Next battery can activate twice."
    )
  end

  def execute_cpu_ability(state, cpu_card, %{type: :siphon_power}, who, target_card_id) do
    {combatant, _} = get_combatants(state, who)
    who_name = if who == :player, do: "You", else: "Enemy"

    target_card = find_card_in_hand(combatant, target_card_id)
    remaining = target_card.properties.remaining_activations + 1

    updated_target = %{
      target_card
      | properties: %{target_card.properties | remaining_activations: remaining}
    }

    combatant = %{combatant | hand: replace_card(combatant.hand, target_card_id, updated_target)}
    combatant = %{combatant | shield: combatant.shield - 2}

    combatant = mark_cpu_activated(combatant, cpu_card)
    state = set_combatant(state, who, combatant)
    state = if who == :player, do: clear_cpu_targeting_state(state), else: state

    add_log(
      state,
      "#{who_name} activates #{cpu_card.name}: Siphoned 2 shield to restore #{target_card.name}."
    )
  end

  def execute_cpu_ability(state, cpu_card, %{type: :extra_activation}, who, target_card_id) do
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

  @doc """
  AI decision-making for CPU ability execution.

  The AI automatically selects the best targets for each ability type:
  - Discard/Draw: Discards worst cards (destroyed > depleted > damaged > others)
  - Reflex Block: Boosts best armor card
  - Target Lock: Uses if weapons are available
  - Overclock: Uses if batteries are available
  - Siphon Power: Restores most-depleted battery
  - Extra Activation: Reactivates best weapon

  Returns the updated combat state.
  """
  @spec ai_execute_cpu_ability(CombatState.t(), Card.t(), map()) :: CombatState.t()
  def ai_execute_cpu_ability(state, cpu_card, %{type: :discard_draw} = ability) do
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

  def ai_execute_cpu_ability(state, cpu_card, %{type: :reflex_block} = ability) do
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

  def ai_execute_cpu_ability(state, cpu_card, %{type: :target_lock} = ability) do
    has_weapons =
      Enum.any?(state.enemy.hand, &(&1.type == :weapon and &1.damage != :destroyed))

    if has_weapons and meets_ability_requirements?(state.enemy, ability) do
      execute_cpu_ability(state, cpu_card, ability, :enemy, nil)
    else
      state
    end
  end

  def ai_execute_cpu_ability(state, cpu_card, %{type: :overclock_battery} = ability) do
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

  def ai_execute_cpu_ability(state, cpu_card, %{type: :siphon_power} = ability) do
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

  def ai_execute_cpu_ability(state, cpu_card, %{type: :extra_activation} = ability) do
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

  # --- Private Helpers ---

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
          {:ok,
           %{
             state
             | cpu_targeting: card.id,
               cpu_discard_selected: [],
               cpu_targeting_mode: :select_hand_cards
           }}
        end

      :reflex_block ->
        if not has_valid_armor_target?(state.player) do
          {:error, "No armor cards in hand to boost."}
        else
          {:ok,
           %{
             state
             | cpu_targeting: card.id,
               cpu_targeting_mode: :select_installed_card,
               cpu_selected_installed: nil
           }}
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
            {:ok,
             %{
               state
               | cpu_targeting: card.id,
                 cpu_targeting_mode: :select_installed_card,
                 cpu_selected_installed: nil
             }}
        end

      :extra_activation ->
        if not has_valid_extra_activation_target?(state.player) do
          {:error, "No activated cards to reactivate."}
        else
          {:ok,
           %{
             state
             | cpu_targeting: card.id,
               cpu_targeting_mode: :select_installed_card,
               cpu_selected_installed: nil
           }}
        end
    end
  end

  defp cpu_has_power?(robot, cpu_card) do
    all_cards = robot.deck ++ robot.hand ++ robot.discard ++ robot.installed

    battery_count =
      Enum.count(all_cards, fn card ->
        card.type == :battery and card.damage != :destroyed and
          Map.get(card.properties, :remaining_activations, 0) > 0
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

  defp has_enough_hand_cards?(robot, %{discard_count: n}) do
    discardable = Enum.reject(robot.hand, &card_used_this_turn?/1)
    length(discardable) >= n
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

  defp card_fully_activated?(card) do
    max_per_turn = Map.get(card.properties, :max_activations_per_turn)

    if max_per_turn do
      Map.get(card.properties, :activations_this_turn, 0) >= max_per_turn
    else
      Map.get(card.properties, :activated_this_turn, false)
    end
  end

  defp card_used_this_turn?(card) do
    Map.get(card.properties, :activated_this_turn, false)
  end

  defp find_card_in_hand(robot, card_id) do
    Enum.find(robot.hand, &(&1.id == card_id))
  end

  defp find_installed_card(robot, card_id) do
    Enum.find(robot.installed, &(&1.id == card_id))
  end

  defp replace_card(cards, card_id, updated_card) do
    Enum.map(cards, fn
      %Card{id: ^card_id} -> updated_card
      card -> card
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

  defp clear_cpu_targeting_state(state) do
    %{
      state
      | cpu_targeting: nil,
        cpu_discard_selected: [],
        cpu_targeting_mode: nil,
        cpu_selected_installed: nil
    }
  end

  defp get_combatants(state, :player), do: {state.player, state.enemy}
  defp get_combatants(state, :enemy), do: {state.enemy, state.player}

  defp set_combatant(state, :player, combatant), do: %{state | player: combatant}
  defp set_combatant(state, :enemy, combatant), do: %{state | enemy: combatant}

  defp add_log(state, message) do
    %{state | log: [message | state.log]}
  end
end
