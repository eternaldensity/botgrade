defmodule Botgrade.Game.Dice do
  @type die :: %{sides: pos_integer(), value: pos_integer()}

  @spec roll(pos_integer(), pos_integer()) :: [die()]
  def roll(count, sides) when count > 0 and sides > 0 do
    Enum.map(1..count, fn _ -> %{sides: sides, value: :rand.uniform(sides)} end)
  end

  @spec roll(pos_integer(), pos_integer(), (pos_integer() -> pos_integer())) :: [die()]
  def roll(count, sides, rng_fun) when count > 0 and sides > 0 do
    Enum.map(1..count, fn _ -> %{sides: sides, value: rng_fun.(sides)} end)
  end
end
