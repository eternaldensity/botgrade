defmodule Botgrade.Game.ScavengeLogic do
  alias Botgrade.Game.{CombatState, Card}

  @scavenge_limit 3

  @spec begin_scavenge(CombatState.t()) :: CombatState.t()
  def begin_scavenge(%CombatState{result: :player_wins} = state) do
    enemy = state.enemy
    all_cards = enemy.deck ++ enemy.hand ++ enemy.discard ++ enemy.in_play

    damage_ratio = 1.0 - enemy.current_hp / max(enemy.total_hp, 1)

    loot =
      all_cards
      |> Enum.map(&apply_scavenge_damage(&1, damage_ratio))
      |> Enum.reject(&(&1.damage == :destroyed))
      |> Enum.map(&reset_card_state/1)

    %{state | phase: :scavenging, scavenge_loot: loot, scavenge_selected: [], scavenge_limit: @scavenge_limit}
    |> add_log("Scavenging enemy wreckage... (pick up to #{@scavenge_limit} cards)")
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
    all_player_cards = player.deck ++ player.hand ++ player.discard ++ player.in_play ++ taken_cards
    updated_player = %{player | deck: all_player_cards, hand: [], discard: [], in_play: []}

    log_msg =
      if taken_cards == [],
        do: "Scavenged nothing.",
        else: "Scavenged: #{Enum.map_join(taken_cards, ", ", & &1.name)}"

    %{state | phase: :ended, player: updated_player}
    |> add_log(log_msg)
  end

  # --- Private ---

  defp apply_scavenge_damage(%Card{damage: :destroyed} = card, _ratio), do: card

  defp apply_scavenge_damage(%Card{damage: :damaged} = card, ratio) do
    if :rand.uniform() < ratio * 0.5, do: %{card | damage: :destroyed}, else: card
  end

  defp apply_scavenge_damage(%Card{} = card, ratio) do
    roll = :rand.uniform()

    cond do
      roll < ratio * 0.3 -> %{card | damage: :destroyed}
      roll < ratio -> %{card | damage: :damaged}
      true -> card
    end
  end

  defp reset_card_state(card) do
    card = %{card | dice_slots: Enum.map(card.dice_slots, &%{&1 | assigned_die: nil})}

    case card.type do
      :battery ->
        props = card.properties
        %{card | properties: %{props | remaining_activations: props.max_activations} |> Map.delete(:activated_this_turn)}

      _ ->
        card
    end
  end

  defp add_log(state, message) do
    %{state | log: [message | state.log]}
  end
end
