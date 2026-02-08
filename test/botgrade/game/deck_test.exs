defmodule Botgrade.Game.DeckTest do
  use ExUnit.Case, async: true

  alias Botgrade.Game.{Deck, Card}

  defp make_cards(n) do
    Enum.map(1..n, fn i ->
      %Card{id: "card_#{i}", name: "Card #{i}", type: :chassis, properties: %{hp_max: 1}}
    end)
  end

  test "draw/2 draws the requested number of cards" do
    cards = make_cards(10)
    {drawn, remaining} = Deck.draw(cards, 5)
    assert length(drawn) == 5
    assert length(remaining) == 5
  end

  test "draw/2 draws all available when requesting more than deck size" do
    cards = make_cards(3)
    {drawn, remaining} = Deck.draw(cards, 5)
    assert length(drawn) == 3
    assert remaining == []
  end

  test "draw/2 from empty deck returns empty" do
    {drawn, remaining} = Deck.draw([], 5)
    assert drawn == []
    assert remaining == []
  end

  test "shuffle_discard_into_deck/2 combines both piles" do
    deck = make_cards(3)
    discard = make_cards(2) |> Enum.map(&%{&1 | id: "discard_#{&1.id}"})
    result = Deck.shuffle_discard_into_deck(deck, discard)
    assert length(result) == 5
  end
end
