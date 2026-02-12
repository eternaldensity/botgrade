defmodule Botgrade.Game.Deck do
  alias Botgrade.Game.Card

  @spec draw([Card.t()], non_neg_integer()) :: {[Card.t()], [Card.t()]}
  def draw(deck, n) do
    {drawn, remaining} = Enum.split(deck, min(n, length(deck)))
    {Enum.map(drawn, &sanitize_drawn/1), remaining}
  end

  # Strips per-turn state from drawn cards so they never arrive in hand
  # with stale flags from a previous turn (e.g. activated_this_turn).
  defp sanitize_drawn(%Card{} = card) do
    props =
      card.properties
      |> Map.delete(:activated_this_turn)
      |> Map.delete(:activations_this_turn)

    %{card | properties: props, last_result: nil}
  end

  @spec shuffle_discard_into_deck([Card.t()], [Card.t()]) :: [Card.t()]
  def shuffle_discard_into_deck(deck, discard) do
    Enum.shuffle(deck ++ discard)
  end
end
