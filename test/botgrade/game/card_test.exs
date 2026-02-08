defmodule Botgrade.Game.CardTest do
  use ExUnit.Case, async: true

  alias Botgrade.Game.Card

  describe "meets_condition?/2" do
    test "nil condition accepts any value" do
      assert Card.meets_condition?(nil, 1)
      assert Card.meets_condition?(nil, 6)
    end

    test "min condition" do
      assert Card.meets_condition?({:min, 3}, 3)
      assert Card.meets_condition?({:min, 3}, 6)
      refute Card.meets_condition?({:min, 3}, 2)
    end

    test "max condition" do
      assert Card.meets_condition?({:max, 4}, 4)
      assert Card.meets_condition?({:max, 4}, 1)
      refute Card.meets_condition?({:max, 4}, 5)
    end

    test "exact condition" do
      assert Card.meets_condition?({:exact, 5}, 5)
      refute Card.meets_condition?({:exact, 5}, 4)
    end

    test "even condition" do
      assert Card.meets_condition?(:even, 2)
      assert Card.meets_condition?(:even, 4)
      refute Card.meets_condition?(:even, 3)
    end

    test "odd condition" do
      assert Card.meets_condition?(:odd, 3)
      assert Card.meets_condition?(:odd, 5)
      refute Card.meets_condition?(:odd, 2)
    end
  end
end
