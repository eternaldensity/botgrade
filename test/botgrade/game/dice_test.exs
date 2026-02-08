defmodule Botgrade.Game.DiceTest do
  use ExUnit.Case, async: true

  alias Botgrade.Game.Dice

  test "roll/2 returns correct number of dice" do
    result = Dice.roll(3, 6)
    assert length(result) == 3
  end

  test "roll/2 returns values within range" do
    results = Dice.roll(100, 6)

    for die <- results do
      assert die.sides == 6
      assert die.value >= 1
      assert die.value <= 6
    end
  end

  test "roll/3 uses provided RNG function" do
    always_max = fn sides -> sides end
    result = Dice.roll(3, 8, always_max)

    assert length(result) == 3

    for die <- result do
      assert die.sides == 8
      assert die.value == 8
    end
  end

  test "roll/3 with deterministic sequence" do
    values = [3, 1, 4]
    agent = start_supervised!({Agent, fn -> values end})

    rng = fn _sides ->
      Agent.get_and_update(agent, fn [h | t] -> {h, t} end)
    end

    result = Dice.roll(3, 6, rng)
    assert Enum.map(result, & &1.value) == [3, 1, 4]
  end
end
