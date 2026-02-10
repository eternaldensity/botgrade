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
          cpu_discard_selected: [String.t()],
          cpu_targeting_mode: :select_hand_cards | :select_installed_card | nil,
          cpu_selected_installed: String.t() | nil,
          target_lock_active: boolean(),
          overclock_active: boolean(),
          overcharge_bonus: non_neg_integer(),
          weapon_activations_this_turn: non_neg_integer(),
          dice_rolled_this_turn: non_neg_integer(),
          cards_drawn_this_turn: non_neg_integer()
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
    cpu_discard_selected: [],
    cpu_targeting_mode: nil,
    cpu_selected_installed: nil,
    target_lock_active: false,
    overclock_active: false,
    overcharge_bonus: 0,
    weapon_activations_this_turn: 0,
    dice_rolled_this_turn: 0,
    cards_drawn_this_turn: 0
  ]
end
