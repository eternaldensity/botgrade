defmodule Botgrade.Game.CombatLogic do
  @moduledoc """
  Main orchestrator for combat gameplay.

  This module coordinates combat flow and delegates to specialized modules:
  - BatteryLogic: Battery activation
  - CPULogic: CPU abilities
  - DiceLogic: Dice allocation
  - CardActivation: Immediate card activation
  - WeaponResolution: Batch weapon/armor resolution
  - EndTurnEffects: End-of-turn weapon effects
  - VictoryLogic: Win/loss conditions
  """

  alias Botgrade.Game.{
    CombatState,
    Robot,
    Card,
    Deck,
    BatteryLogic,
    CPULogic,
    DiceLogic,
    WeaponResolution,
    EndTurnEffects,
    ElementLogic,
    VictoryLogic
  }

  @draw_count 5
  @enemy_draw_count 4

  # --- Initialization ---

  @doc """
  Creates a new combat state with the given player and enemy cards.

  Optional player_resources map can include scrap, credits, etc.
  """
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

  @doc """
  Executes the draw phase for the player.

  Resets shield, draws cards, and transitions to power_up phase.
  """
  @spec draw_phase(CombatState.t()) :: CombatState.t()
  def draw_phase(%CombatState{phase: :draw, turn_owner: :player} = state) do
    state = ElementLogic.process_start_of_turn_elements(state, :player)

    # Shield resets at start of turn, not end — so it protects during enemy attacks
    player = %{state.player | shield: 0}

    # Draw cards and apply fused effects to drawn cards
    {drawn, player} = draw_raw_cards(player, @draw_count)
    {drawn, state, fused_logs} = ElementLogic.apply_fused_to_drawn(drawn, state, :player)
    player = %{player | hand: player.hand ++ drawn}

    state = %{state | player: player, phase: :power_up}
    state = add_log(state, "Turn #{state.turn_number}: Drew #{length(drawn)} cards.")
    Enum.reduce(fused_logs, state, &add_log(&2, &1))
  end

  # --- Battery Activation ---

  @doc """
  Activates a battery card from the player's hand.

  Delegates to BatteryLogic module.
  """
  @spec activate_battery(CombatState.t(), String.t()) ::
          {:ok, CombatState.t()} | {:error, String.t()}
  defdelegate activate_battery(state, card_id), to: BatteryLogic

  # --- Capacitor Abilities ---

  @doc """
  Activates a capacitor ability (e.g. Dynamo: +1 to stored die value).
  """
  @spec activate_capacitor(CombatState.t(), String.t()) ::
          {:ok, CombatState.t()} | {:error, String.t()}
  def activate_capacitor(%CombatState{phase: :power_up} = state, card_id) do
    player = state.player

    case Enum.find(player.hand, &(&1.id == card_id)) do
      nil ->
        {:error, "Card not found."}

      %Card{type: :capacitor, damage: :destroyed} ->
        {:error, "Card is destroyed."}

      %Card{type: :capacitor} = card ->
        ability = Map.get(card.properties, :capacitor_ability)

        cond do
          ability != :dynamo ->
            {:error, "Card has no activation ability."}

          Map.get(card.properties, :activated_this_turn, false) ->
            {:error, "Already activated this turn."}

          not Enum.any?(card.dice_slots, &(&1.assigned_die != nil)) ->
            {:error, "No stored die to boost."}

          true ->
            boost = Map.get(card.properties, :boost_amount, 1)

            max_val =
              if card.damage == :damaged,
                do: Card.damaged_capacitor_max_value(),
                else: nil

            {updated_slots, boosted?} =
              Enum.map_reduce(card.dice_slots, false, fn slot, already_boosted ->
                case slot.assigned_die do
                  %{value: v} = die when not already_boosted ->
                    new_val =
                      if max_val, do: min(v + boost, max_val), else: v + boost

                    if new_val == v do
                      {slot, false}
                    else
                      {%{slot | assigned_die: %{die | value: new_val}}, true}
                    end

                  _ ->
                    {slot, already_boosted}
                end
              end)

            if not boosted? do
              {:error, "Cannot boost die (at maximum)."}
            else
              boosted_die = Enum.find(updated_slots, &(&1.assigned_die != nil)).assigned_die
              props = Map.put(card.properties, :activated_this_turn, true)
              updated_card = %{card | dice_slots: updated_slots, properties: props}
              player = %{player | hand: replace_card(player.hand, card_id, updated_card)}

              state =
                %{state | player: player}
                |> add_log("Dynamo activated! Stored die boosted to #{boosted_die.value}.")

              {:ok, state}
            end
        end

      _ ->
        {:error, "Not a capacitor."}
    end
  end

  def activate_capacitor(_state, _card_id), do: {:error, "Not in power up phase."}

  # --- CPU Abilities ---

  @doc """
  Initiates CPU ability activation.

  Delegates to CPULogic module.
  """
  @spec activate_cpu(CombatState.t(), String.t()) :: {:ok, CombatState.t()} | {:error, String.t()}
  defdelegate activate_cpu(state, card_id), to: CPULogic

  @doc """
  Toggles a card in the discard selection for CPU discard_draw abilities.

  Delegates to CPULogic module.
  """
  @spec toggle_cpu_discard(CombatState.t(), String.t()) ::
          {:ok, CombatState.t()} | {:error, String.t()}
  defdelegate toggle_cpu_discard(state, card_id), to: CPULogic

  @doc """
  Selects a target card for CPU abilities.

  Delegates to CPULogic module.
  """
  @spec select_cpu_target_card(CombatState.t(), String.t()) ::
          {:ok, CombatState.t()} | {:error, String.t()}
  defdelegate select_cpu_target_card(state, card_id), to: CPULogic

  @doc """
  Confirms and executes the CPU ability.

  Delegates to CPULogic module.
  """
  @spec confirm_cpu_ability(CombatState.t()) :: {:ok, CombatState.t()} | {:error, String.t()}
  defdelegate confirm_cpu_ability(state), to: CPULogic

  @doc """
  Cancels CPU targeting mode.

  Delegates to CPULogic module.
  """
  @spec cancel_cpu_ability(CombatState.t()) :: {:ok, CombatState.t()} | {:error, String.t()}
  defdelegate cancel_cpu_ability(state), to: CPULogic

  # --- Dice Allocation ---

  @doc """
  Allocates a die to a card slot.

  Delegates to DiceLogic module.
  """
  @spec allocate_die(CombatState.t(), non_neg_integer(), String.t(), String.t()) ::
          {:ok, CombatState.t()} | {:error, String.t()}
  defdelegate allocate_die(state, die_index, card_id, slot_id), to: DiceLogic

  @doc """
  Unallocates a die from a card slot.

  Delegates to DiceLogic module.
  """
  @spec unallocate_die(CombatState.t(), String.t(), String.t()) ::
          {:ok, CombatState.t()} | {:error, String.t()}
  defdelegate unallocate_die(state, card_id, slot_id), to: DiceLogic

  # --- End Turn ---

  @doc """
  Ends the player's turn and transitions to enemy turn or victory.

  Clears CPU targeting, resets buffs, processes cleanup, and checks victory.
  """
  @spec end_turn(CombatState.t()) :: CombatState.t()
  def end_turn(%CombatState{phase: :power_up} = state) do
    state
    |> clear_cpu_targeting_state()
    |> Map.put(:target_lock_active, false)
    |> Map.put(:overclock_active, false)
    |> cleanup_turn(:player)
    |> VictoryLogic.check_victory()
    |> maybe_transition_to_enemy()
  end

  # Victory was already determined mid-turn (e.g. from card activation)
  def end_turn(%CombatState{result: result} = state) when result != :ongoing, do: state

  # --- Enemy Turn ---

  @doc """
  Executes the enemy's turn with all AI logic.

  Draws cards, activates CPUs, batteries, allocates dice, resolves cards,
  performs cleanup, checks victory, and transitions to next turn.
  """
  @spec enemy_turn(CombatState.t()) :: CombatState.t()
  def enemy_turn(%CombatState{phase: :enemy_turn} = state) do
    state = ElementLogic.process_start_of_turn_elements(state, :enemy)

    # Shield resets at start of turn, not end — so it protects during opponent attacks
    enemy = %{state.enemy | shield: 0}
    {drawn, enemy} = draw_raw_cards(enemy, @enemy_draw_count)
    {drawn, state, fused_logs} = ElementLogic.apply_fused_to_drawn(drawn, state, :enemy)
    enemy = %{enemy | hand: enemy.hand ++ drawn}
    state = %{state | enemy: enemy} |> add_log("Enemy draws #{length(drawn)} cards.")
    state = Enum.reduce(fused_logs, state, &add_log(&2, &1))

    state = ai_use_cpu_ability(state, :pre_battery)
    state = activate_all_batteries(state, :enemy)
    state = ai_use_cpu_ability(state, :post_battery)
    state = DiceLogic.ai_allocate_dice(state)

    state
    |> WeaponResolution.resolve_armor(:enemy)
    |> WeaponResolution.resolve_weapons(:enemy)
    |> cleanup_turn(:enemy)
    |> VictoryLogic.check_victory()
    |> next_turn()
  end

  @doc """
  Executes the enemy's turn with events for animation timing.

  Returns {final_state, events} where events is a list of {state, delay_ms} tuples.
  """
  @spec enemy_turn_with_events(CombatState.t()) ::
          {CombatState.t(), [{CombatState.t(), non_neg_integer()}]}
  def enemy_turn_with_events(%CombatState{phase: :enemy_turn} = state) do
    events = []

    state = ElementLogic.process_start_of_turn_elements(state, :enemy)

    # Draw phase — shield resets at start of turn so it protects during opponent attacks
    enemy = %{state.enemy | shield: 0}
    {drawn, enemy} = draw_raw_cards(enemy, @enemy_draw_count)
    {drawn, state, fused_logs} = ElementLogic.apply_fused_to_drawn(drawn, state, :enemy)
    enemy = %{enemy | hand: enemy.hand ++ drawn}
    state = %{state | enemy: enemy} |> add_log("Enemy draws #{length(drawn)} cards.")
    state = Enum.reduce(fused_logs, state, &add_log(&2, &1))
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
    state = DiceLogic.ai_allocate_dice(state)
    events = events ++ [{state, 400}]

    # Armor resolution (one event per armor)
    {state, armor_events} = WeaponResolution.resolve_armor_with_events(state, :enemy)
    events = events ++ armor_events

    # Weapon resolution (one event per weapon hit)
    {state, weapon_events} = WeaponResolution.resolve_weapons_with_events(state, :enemy)
    events = events ++ weapon_events

    # Cleanup + check victory + next turn
    state = state |> cleanup_turn(:enemy) |> VictoryLogic.check_victory() |> next_turn()
    events = events ++ [{state, 0}]

    {state, events}
  end

  # --- Private Helpers ---

  defp maybe_transition_to_enemy(%CombatState{result: :ongoing} = state) do
    %{state | phase: :enemy_turn}
  end

  defp maybe_transition_to_enemy(state), do: state

  defp activate_all_batteries_with_events(state) do
    batteries =
      state.enemy.hand
      |> Enum.filter(&(&1.type == :battery))
      |> Enum.filter(&(&1.damage != :destroyed))
      |> Enum.filter(&(&1.properties.remaining_activations > 0))

    {state, events} =
      Enum.reduce(batteries, {state, []}, fn battery, {acc_state, acc_events} ->
        acc_state = BatteryLogic.activate_enemy_battery(acc_state, battery)
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
          |> BatteryLogic.activate_enemy_battery(overclock_target)
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

          add_log(
            acc_state,
            "Enemy #{cpu_card.name} malfunctions! Ability failed (damaged)."
          )
        else
          CPULogic.ai_execute_cpu_ability(acc_state, cpu_card, cpu_card.properties.cpu_ability)
        end

      {acc_state, acc_events ++ [{acc_state, delay}]}
    end)
  end

  defp cleanup_turn(state, who) do
    # Process end-of-turn weapon effects before cleanup
    state = EndTurnEffects.process_end_of_turn_weapons(state, who)

    # Process element end-of-turn effects (rust damage, clear transient statuses)
    state = ElementLogic.process_end_of_turn_elements(state, who)

    {combatant, _} = get_combatants(state, who)

    # Clear dice from non-capacitor card slots and clear locked flags
    hand_cards = clear_dice_from_cards(combatant.hand)

    # Clear activation flags, results, shield_base_bonus, and locked slots
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

        # Clear locked flag from any remaining locked slots
        updated_slots = Enum.map(card.dice_slots, &Map.delete(&1, :locked))

        %{card | properties: props, dice_slots: updated_slots}
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
        available_dice: []
    }

    state =
      if who == :player,
        do: %{state | player: combatant},
        else: %{state | enemy: combatant}

    # Reset per-turn state
    %{state | overcharge_bonus: 0, weapon_activations_this_turn: 0, dice_rolled_this_turn: 0, cards_drawn_this_turn: 0}
  end

  defp activate_all_batteries(state, :enemy) do
    batteries =
      state.enemy.hand
      |> Enum.filter(&(&1.type == :battery))
      |> Enum.filter(&(&1.damage != :destroyed))
      |> Enum.filter(&(&1.properties.remaining_activations > 0))

    state =
      Enum.reduce(batteries, state, fn battery, acc_state ->
        BatteryLogic.activate_enemy_battery(acc_state, battery)
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
        |> BatteryLogic.activate_enemy_battery(overclock_target)
        |> Map.put(:overclock_active, false)
      else
        %{state | overclock_active: false}
      end
    else
      state
    end
  end

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
        CPULogic.ai_execute_cpu_ability(acc_state, cpu_card, cpu_card.properties.cpu_ability)
      end
    end)
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

  defp next_turn(%CombatState{result: :ongoing} = state) do
    %{state | phase: :draw, turn_owner: :player, turn_number: state.turn_number + 1}
  end

  defp next_turn(state), do: state

  # Draws cards from the robot's deck, returning {drawn_cards, updated_robot}.
  # The drawn cards are NOT added to hand — caller is responsible for that
  # (allows intercepting drawn cards for element effects like Fused).
  defp draw_raw_cards(robot, count) do
    {deck, discard} =
      if length(robot.deck) < count and length(robot.discard) > 0 do
        {Deck.shuffle_discard_into_deck(robot.deck, robot.discard), []}
      else
        {robot.deck, robot.discard}
      end

    {drawn, remaining} = Deck.draw(deck, count)
    {drawn, %{robot | deck: remaining, discard: discard}}
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

  defp replace_card(cards, card_id, updated_card) do
    Enum.map(cards, fn
      %Card{id: ^card_id} -> updated_card
      card -> card
    end)
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

  defp add_log(state, message) do
    %{state | log: [message | state.log]}
  end
end
