defmodule Botgrade.Game.ScavengeLogic do
  alias Botgrade.Game.{CombatState, Card, ScrapLogic}

  @scavenge_limit 3

  @spec begin_scavenge(CombatState.t()) :: CombatState.t()
  def begin_scavenge(%CombatState{result: :player_wins} = state) do
    enemy = state.enemy
    player = state.player

    all_enemy_cards = enemy.installed ++ enemy.deck ++ enemy.hand ++ enemy.discard
    all_player_cards = player.installed ++ player.deck ++ player.hand ++ player.discard

    # Generate scrap from destroyed cards on BOTH sides (before salvage degradation)
    scraps = ScrapLogic.generate_scrap_from_cards(all_enemy_cards ++ all_player_cards)

    # Cards already have combat damage state; apply light salvage degradation
    loot =
      all_enemy_cards
      |> Enum.map(&apply_scavenge_degradation/1)
      |> Enum.reject(&(&1.damage == :destroyed))
      |> Enum.map(&reset_card_state/1)

    scrap_msg =
      if map_size(scraps) > 0,
        do: "Scrap recovered: #{ScrapLogic.format_resources(scraps)}",
        else: "No usable scrap found in the wreckage."

    %{state |
      phase: :scavenging,
      scavenge_loot: loot,
      scavenge_selected: [],
      scavenge_limit: @scavenge_limit,
      scavenge_scraps: scraps
    }
    |> add_log("Scavenging enemy wreckage... (pick up to #{@scavenge_limit} cards)")
    |> add_log(scrap_msg)
  end

  @spec toggle_card(CombatState.t(), String.t()) :: {:ok, CombatState.t()} | {:error, String.t()}
  def toggle_card(%CombatState{phase: :scavenging} = state, card_id) do
    cond do
      card_id in state.scavenge_selected ->
        {:ok, %{state | scavenge_selected: List.delete(state.scavenge_selected, card_id)}}

      length(state.scavenge_selected) >= state.scavenge_limit ->
        {:error, "Cannot select more than #{state.scavenge_limit} cards."}

      Enum.any?(state.scavenge_loot, &(&1.id == card_id)) ->
        {:ok, %{state | scavenge_selected: state.scavenge_selected ++ [card_id]}}

      true ->
        {:error, "Card not found in loot."}
    end
  end

  @spec confirm_scavenge(CombatState.t()) :: CombatState.t()
  def confirm_scavenge(%CombatState{phase: :scavenging} = state) do
    taken_cards =
      state.scavenge_loot
      |> Enum.filter(&(&1.id in state.scavenge_selected))
      |> Enum.map(fn card ->
        %{card | id: "scav_#{card.id}_#{:rand.uniform(999_999)}"}
      end)

    player = state.player

    all_player_cards =
      (player.installed ++ player.deck ++ player.hand ++ player.discard ++ taken_cards)
      |> Enum.reject(&(&1.damage == :destroyed))
      |> Enum.map(&reset_card_state/1)
    merged_resources = ScrapLogic.merge_resources(player.resources, state.scavenge_scraps)
    updated_player = %{player | deck: all_player_cards, hand: [], discard: [], installed: [], resources: merged_resources}

    log_msg =
      if taken_cards == [],
        do: "Scavenged nothing.",
        else: "Scavenged: #{Enum.map_join(taken_cards, ", ", & &1.name)}"

    %{state | phase: :ended, player: updated_player}
    |> add_log(log_msg)
  end

  # --- Private ---

  # Lighter post-combat degradation since cards already took damage during combat
  defp apply_scavenge_degradation(%Card{damage: :destroyed} = card), do: card

  defp apply_scavenge_degradation(%Card{damage: :damaged} = card) do
    # 20% chance damaged cards break during salvage
    if :rand.uniform() < 0.2, do: %{card | damage: :destroyed, current_hp: 0}, else: card
  end

  defp apply_scavenge_degradation(%Card{} = card) do
    # 10% chance intact cards get damaged during salvage
    if :rand.uniform() < 0.1 do
      max_hp = Map.get(card.properties, :card_hp, 2)
      %{card | damage: :damaged, current_hp: div(max_hp, 2)}
    else
      card
    end
  end

  defp reset_card_state(card) do
    # Capacitors retain their stored dice between fights
    cleared_slots =
      if card.type == :capacitor,
        do: card.dice_slots,
        else: Enum.map(card.dice_slots, &%{&1 | assigned_die: nil})

    card = %{card |
      dice_slots: cleared_slots,
      last_result: nil
    }

    # Set current_hp to match damage state
    max_hp = Map.get(card.properties, :card_hp, 2)

    card =
      case card.damage do
        :intact -> %{card | current_hp: max_hp}
        :damaged -> %{card | current_hp: div(max_hp, 2)}
        :destroyed -> %{card | current_hp: 0}
      end

    props = Map.delete(card.properties, :overkill)

    props = Map.delete(props, :activated_this_turn)

    case card.type do
      :battery ->
        %{card | properties: %{props | remaining_activations: props.max_activations}}

      _ ->
        %{card | properties: props}
    end
  end

  defp add_log(state, message) do
    %{state | log: [message | state.log]}
  end
end
