defmodule Botgrade.Game.Targeting do
  alias Botgrade.Game.{Card, Robot}

  @default_profile %{
    weapon: 15,
    armor: 15,
    battery: 15,
    capacitor: 10,
    chassis: 15,
    locomotion: 15,
    cpu: 15
  }

  @spec default_profile() :: map()
  def default_profile, do: @default_profile

  @doc """
  Returns all alive cards on a robot that can be targeted by attacks.
  Includes installed, in_play, and hand cards with current_hp > 0.
  """
  @spec targetable_cards(Robot.t()) :: [Card.t()]
  def targetable_cards(robot) do
    (robot.installed ++ robot.in_play ++ robot.hand)
    |> Enum.filter(&(&1.current_hp != nil and &1.current_hp > 0))
  end

  @doc """
  Selects a target card using weighted random selection based on the weapon's
  targeting profile. Weights are keyed by card type and normalized against
  only the types actually present in the target list.
  """
  @spec select_target(map() | nil, [Card.t()]) :: Card.t() | nil
  def select_target(_profile, []), do: nil

  def select_target(profile, targetable_cards) do
    profile = profile || @default_profile

    weighted =
      Enum.map(targetable_cards, fn card ->
        weight = Map.get(profile, card.type, 1)
        {card, max(weight, 1)}
      end)

    total_weight = Enum.reduce(weighted, 0, fn {_, w}, acc -> acc + w end)

    if total_weight <= 0 do
      Enum.random(targetable_cards)
    else
      roll = :rand.uniform(total_weight)
      pick_weighted(weighted, roll)
    end
  end

  defp pick_weighted([{card, weight} | _rest], roll) when roll <= weight, do: card
  defp pick_weighted([{_card, weight} | rest], roll), do: pick_weighted(rest, roll - weight)
  defp pick_weighted([], _roll), do: nil
end
