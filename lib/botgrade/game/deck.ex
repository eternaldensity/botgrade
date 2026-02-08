defmodule Botgrade.Game.Deck do
  alias Botgrade.Game.Card

  @spec draw([Card.t()], non_neg_integer()) :: {[Card.t()], [Card.t()]}
  def draw(deck, n) do
    {drawn, remaining} = Enum.split(deck, min(n, length(deck)))
    {drawn, remaining}
  end

  @spec shuffle_discard_into_deck([Card.t()], [Card.t()]) :: [Card.t()]
  def shuffle_discard_into_deck(deck, discard) do
    Enum.shuffle(deck ++ discard)
  end
end
