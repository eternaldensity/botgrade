defmodule Botgrade.Game.ElementLogic do
  @moduledoc """
  Handles element status effects in combat.

  Elements are a separate property from damage types (kinetic/energy/plasma).
  When an elemental weapon hits, it applies a status effect to the defender:

  - Fire → Overheated N: First N dice rolled next turn gain :blazing (deal 1 damage to card when used)
  - Ice → Subzero N: First N dice rolled next turn are forced to value 1
  - Magnetic → Fused N: First N cards drawn next turn have their power slots locked
  - Dark → Hidden N: First N dice rolled next turn have hidden values (shown as "?")
  - Water → Rust N: Deals N damage to a random component at end of turn (persists, -1 per turn)
  """

  alias Botgrade.Game.{CombatState, Card}

  @element_to_status %{
    fire: :overheated,
    ice: :subzero,
    magnetic: :fused,
    dark: :hidden,
    water: :rust
  }

  # --- Status Application (called when an elemental weapon hits) ---

  @doc """
  Applies element status from an attacker's weapon to the defender.
  Called after a weapon deals damage if the weapon has an :element property.
  `who` is the attacker — the defender is the opposite side.
  """
  @spec apply_element_status(CombatState.t(), Card.t(), :player | :enemy) :: CombatState.t()
  def apply_element_status(state, weapon, who) do
    element =
      if Map.get(weapon.properties, :random_element, false) do
        Enum.random([:fire, :ice, :magnetic, :dark, :water])
      else
        Map.get(weapon.properties, :element)
      end

    stacks = Map.get(weapon.properties, :element_stacks, 1)

    if element do
      status = Map.fetch!(@element_to_status, element)
      defender = get_defender(state, who)
      current = Map.get(defender.status_effects, status, 0)
      defender = %{defender | status_effects: Map.put(defender.status_effects, status, current + stacks)}
      defender_label = if who == :player, do: "Enemy", else: "You"

      state
      |> set_defender(who, defender)
      |> add_log("#{defender_label} gains #{status_label(status)} #{current + stacks}! (+#{stacks})")
    else
      state
    end
  end

  # --- Start-of-Turn Processing ---

  @doc """
  Called at the beginning of a combatant's turn.
  Resets per-turn counters for element effect tracking.
  """
  @spec process_start_of_turn_elements(CombatState.t(), :player | :enemy) :: CombatState.t()
  def process_start_of_turn_elements(state, _who) do
    %{state | dice_rolled_this_turn: 0, cards_drawn_this_turn: 0}
  end

  # --- Dice Effects (called after each battery activation rolls dice) ---

  @doc """
  Called after dice are rolled by a battery activation.
  Applies subzero (force value=1), blazing, and hidden tags to the
  first N dice that haven't been processed yet this turn.

  Uses `dice_rolled_this_turn` as the global index to track which dice
  are "first N" across multiple battery activations.

  Returns {processed_dice, updated_state}.
  """
  @spec apply_dice_effects([map()], CombatState.t(), :player | :enemy) :: {[map()], CombatState.t()}
  def apply_dice_effects(new_dice, state, who) do
    combatant = get_combatant(state, who)
    effects = combatant.status_effects
    already_rolled = state.dice_rolled_this_turn

    subzero_n = Map.get(effects, :subzero, 0)
    blazing_n = Map.get(effects, :overheated, 0)
    hidden_n = Map.get(effects, :hidden, 0)

    {processed_dice, _idx, logs} =
      Enum.reduce(new_dice, {[], already_rolled, []}, fn die, {acc, global_idx, logs} ->
        {die, new_logs} = apply_single_die_effects(die, global_idx, subzero_n, blazing_n, hidden_n)
        {acc ++ [die], global_idx + 1, logs ++ new_logs}
      end)

    state = %{state | dice_rolled_this_turn: already_rolled + length(new_dice)}
    state = Enum.reduce(logs, state, &add_log(&2, &1))
    {processed_dice, state}
  end

  defp apply_single_die_effects(die, global_idx, subzero_n, blazing_n, hidden_n) do
    logs = []

    {die, logs} =
      if global_idx < subzero_n do
        {%{die | value: 1}, logs ++ ["Subzero freezes die to 1!"]}
      else
        {die, logs}
      end

    die = if global_idx < blazing_n, do: Map.put(die, :blazing, true), else: die
    die = if global_idx < hidden_n, do: Map.put(die, :hidden, true), else: die
    {die, logs}
  end

  # --- Fused: Lock card slots on drawn cards ---

  @doc """
  Called after cards are drawn in the draw phase.
  For each drawn card (up to fused_n remaining), locks all power slots.
  Batteries drawn when fused get +1 remaining_activations instead.

  Returns {updated_drawn_cards, updated_state, log_messages}.
  """
  @spec apply_fused_to_drawn([Card.t()], CombatState.t(), :player | :enemy) ::
          {[Card.t()], CombatState.t(), [String.t()]}
  def apply_fused_to_drawn(drawn_cards, state, who) do
    combatant = get_combatant(state, who)
    fused_n = Map.get(combatant.status_effects, :fused, 0)
    already_drawn = state.cards_drawn_this_turn

    {processed_cards, _idx, logs} =
      Enum.reduce(drawn_cards, {[], already_drawn, []}, fn card, {acc, global_idx, logs} ->
        if global_idx < fused_n do
          {card, msg} = apply_fused_to_card(card)
          {acc ++ [card], global_idx + 1, if(msg, do: logs ++ [msg], else: logs)}
        else
          {acc ++ [card], global_idx + 1, logs}
        end
      end)

    state = %{state | cards_drawn_this_turn: already_drawn + length(drawn_cards)}
    {processed_cards, state, logs}
  end

  defp apply_fused_to_card(%Card{type: :battery} = card) do
    remaining = Map.get(card.properties, :remaining_activations, 0) + 1
    updated = %{card | properties: Map.put(card.properties, :remaining_activations, remaining)}
    {updated, "Fused energy surges into #{card.name}: +1 charge!"}
  end

  defp apply_fused_to_card(%Card{dice_slots: slots} = card) when slots != [] do
    updated_slots = Enum.map(slots, &Map.put(&1, :locked, true))
    {%{card | dice_slots: updated_slots}, "#{card.name} slots locked by Fused!"}
  end

  defp apply_fused_to_card(card), do: {card, nil}

  # --- Blazing Self-Damage (called when a die is allocated to a card) ---

  @doc """
  If a blazing die is assigned to a card slot, deal 1 damage to that card.
  Removes the blazing flag from the die afterward.

  Returns {updated_card, updated_die, log_message | nil}.
  """
  @spec process_blazing_die(Card.t(), map()) :: {Card.t(), map(), String.t() | nil}
  def process_blazing_die(card, die) do
    if Map.get(die, :blazing, false) do
      new_hp = max(0, (card.current_hp || 0) - 1)
      updated_card = %{card | current_hp: new_hp} |> Card.sync_damage_state()
      updated_die = Map.delete(die, :blazing)
      destroyed_msg = if new_hp <= 0, do: " DESTROYED!", else: ""
      msg = "Blazing die burns #{card.name} for 1 damage!#{destroyed_msg}"
      {updated_card, updated_die, msg}
    else
      {card, die, nil}
    end
  end

  # --- End-of-Turn Processing ---

  @doc """
  Process end-of-turn element effects for a combatant:
  1. Rust damage: deal N damage to a random non-CPU, non-battery component
  2. Clear all non-rust statuses (overheated, subzero, fused, hidden)
  3. Reduce rust by 1 (persists!)
  """
  @spec process_end_of_turn_elements(CombatState.t(), :player | :enemy) :: CombatState.t()
  def process_end_of_turn_elements(state, who) do
    combatant = get_combatant(state, who)
    effects = combatant.status_effects

    if effects == %{} do
      state
    else
      # 1. Rust damage
      rust_n = Map.get(effects, :rust, 0)
      state = if rust_n > 0, do: apply_rust_damage(state, who, rust_n), else: state

      # 2. Clear transient statuses, reduce rust by 1
      combatant = get_combatant(state, who)

      new_effects =
        combatant.status_effects
        |> Map.delete(:overheated)
        |> Map.delete(:subzero)
        |> Map.delete(:fused)
        |> Map.delete(:hidden)
        |> Map.update(:rust, 0, fn n -> max(0, n - 1) end)

      new_effects =
        if Map.get(new_effects, :rust, 0) == 0,
          do: Map.delete(new_effects, :rust),
          else: new_effects

      combatant = %{combatant | status_effects: new_effects}
      set_combatant(state, who, combatant)
    end
  end

  defp apply_rust_damage(state, who, rust_n) do
    combatant = get_combatant(state, who)
    who_label = if who == :player, do: "Your", else: "Enemy's"

    # Targetable: installed + hand cards with HP, excluding CPUs and batteries
    targets =
      (combatant.installed ++ combatant.hand)
      |> Enum.filter(fn card ->
        card.current_hp != nil and card.current_hp > 0 and
          card.type not in [:cpu, :battery]
      end)

    if targets != [] do
      target = Enum.random(targets)
      new_hp = max(0, target.current_hp - rust_n)
      updated = %{target | current_hp: new_hp} |> Card.sync_damage_state()

      combatant = update_card_in_zones(combatant, target.id, updated)
      state = set_combatant(state, who, combatant)

      destroyed_msg = if new_hp <= 0, do: " DESTROYED!", else: ""
      add_log(state, "Rust corrodes #{who_label} #{target.name} for #{rust_n} damage!#{destroyed_msg}")
    else
      state
    end
  end

  # --- Helpers ---

  defp status_label(:overheated), do: "Overheated"
  defp status_label(:subzero), do: "Subzero"
  defp status_label(:fused), do: "Fused"
  defp status_label(:hidden), do: "Hidden"
  defp status_label(:rust), do: "Rust"

  defp get_combatant(%CombatState{player: player}, :player), do: player
  defp get_combatant(%CombatState{enemy: enemy}, :enemy), do: enemy

  defp get_defender(state, :player), do: state.enemy
  defp get_defender(state, :enemy), do: state.player

  defp set_defender(state, :player, defender), do: %{state | enemy: defender}
  defp set_defender(state, :enemy, defender), do: %{state | player: defender}

  defp set_combatant(state, :player, combatant), do: %{state | player: combatant}
  defp set_combatant(state, :enemy, combatant), do: %{state | enemy: combatant}

  defp update_card_in_zones(robot, card_id, updated_card) do
    %{
      robot
      | installed: replace_card(robot.installed, card_id, updated_card),
        hand: replace_card(robot.hand, card_id, updated_card)
    }
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
