defmodule Botgrade.Game.CombatState do
  alias Botgrade.Game.{Robot, Card}

  @type phase ::
          :draw
          | :power_up
          | :enemy_turn
          | :scavenging
          | :ended

  @type t :: %__MODULE__{
          id: String.t(),
          player: Robot.t(),
          enemy: Robot.t(),
          phase: phase(),
          turn_number: non_neg_integer(),
          turn_owner: :player | :enemy,
          log: [String.t()],
          result: :ongoing | :player_wins | :enemy_wins,
          scavenge_loot: [Card.t()],
          scavenge_selected: [String.t()],
          scavenge_limit: non_neg_integer(),
          scavenge_scraps: map(),
          cpu_targeting: String.t() | nil,
          cpu_discard_selected: [String.t()]
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
    result: :ongoing,
    scavenge_loot: [],
    scavenge_selected: [],
    scavenge_limit: 3,
    scavenge_scraps: %{},
    last_attack_result: nil,
    cpu_targeting: nil,
    cpu_discard_selected: []
  ]
end
