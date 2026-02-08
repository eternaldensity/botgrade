defmodule Botgrade.Game.CombatState do
  alias Botgrade.Game.Robot

  @type phase ::
          :draw
          | :activate_batteries
          | :allocate_dice
          | :resolve
          | :enemy_turn
          | :ended

  @type t :: %__MODULE__{
          id: String.t(),
          player: Robot.t(),
          enemy: Robot.t(),
          phase: phase(),
          turn_number: non_neg_integer(),
          turn_owner: :player | :enemy,
          log: [String.t()],
          result: :ongoing | :player_wins | :enemy_wins
        }

  @enforce_keys [:id, :player, :enemy]
  defstruct [
    :id,
    :player,
    :enemy,
    phase: :draw,
    turn_number: 1,
    turn_owner: :player,
    log: [],
    result: :ongoing
  ]
end
