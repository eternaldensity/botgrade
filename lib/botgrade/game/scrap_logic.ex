defmodule Botgrade.Game.ScrapLogic do
  alias Botgrade.Game.Card

  @type resource_type :: :metal | :wire | :plastic | :grease | :chips
  @type resource_bag :: %{optional(resource_type()) => non_neg_integer()}

  # Base yield ranges per card type: {resource_type, min, max}
  @scrap_tables %{
    chassis: [{:metal, 2, 4}, {:plastic, 0, 1}],
    weapon: [{:metal, 1, 2}, {:chips, 0, 1}],
    armor: [{:metal, 1, 3}, {:plastic, 0, 1}],
    battery: [{:wire, 1, 2}, {:grease, 0, 1}, {:chips, 0, 1}],
    capacitor: [{:wire, 1, 2}, {:chips, 1, 2}],
    cpu: [{:chips, 2, 3}, {:wire, 0, 1}],
    locomotion: [{:metal, 1, 2}, {:grease, 0, 1}]
  }

  @doc """
  Generates scrap from a single destroyed card.
  Overkill (stored in card.properties) reduces yield via a multiplier.
  """
  @spec generate_scrap(Card.t()) :: resource_bag()
  def generate_scrap(%Card{damage: :destroyed} = card) do
    table = Map.get(@scrap_tables, card.type, [])
    max_hp = Map.get(card.properties, :card_hp, 2)
    overkill = Map.get(card.properties, :overkill, 0)

    # 1.0 at no overkill, floors at 0.25
    multiplier = max(0.25, 1.0 - overkill / max(max_hp, 1))

    Enum.reduce(table, %{}, fn {resource, min_val, max_val}, acc ->
      base = min_val + :rand.uniform(max_val - min_val + 1) - 1
      yield = max(0, floor(base * multiplier))
      if yield > 0, do: Map.put(acc, resource, yield), else: acc
    end)
  end

  def generate_scrap(_card), do: %{}

  @doc """
  Generates scrap from a list of cards, keeping only destroyed ones.
  """
  @spec generate_scrap_from_cards([Card.t()]) :: resource_bag()
  def generate_scrap_from_cards(cards) do
    cards
    |> Enum.filter(&(&1.damage == :destroyed))
    |> Enum.map(&generate_scrap/1)
    |> Enum.reduce(%{}, &merge_resources/2)
  end

  @doc """
  Merges two resource bags, summing matching resource types.
  """
  @spec merge_resources(resource_bag(), resource_bag()) :: resource_bag()
  def merge_resources(a, b) do
    Map.merge(a, b, fn _k, v1, v2 -> v1 + v2 end)
  end

  @doc """
  Formats a resource bag as a human-readable string.
  """
  @spec format_resources(resource_bag()) :: String.t()
  def format_resources(resources) when map_size(resources) == 0, do: "nothing"

  def format_resources(resources) do
    resources
    |> Enum.sort_by(fn {k, _v} -> Atom.to_string(k) end)
    |> Enum.map_join(", ", fn {type, count} ->
      "#{resource_label(type)} x#{count}"
    end)
  end

  defp resource_label(:metal), do: "Metal"
  defp resource_label(:wire), do: "Wire"
  defp resource_label(:plastic), do: "Plastic"
  defp resource_label(:grease), do: "Grease"
  defp resource_label(:chips), do: "Chips"
end
