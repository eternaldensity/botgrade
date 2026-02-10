defmodule Botgrade.Game.Card do
  @type card_type :: :battery | :capacitor | :weapon | :armor | :locomotion | :chassis | :cpu | :utility

  @type dice_condition ::
          {:min, pos_integer()}
          | {:max, pos_integer()}
          | {:exact, pos_integer()}
          | :even
          | :odd

  @type dice_slot :: %{
          id: String.t(),
          condition: dice_condition() | nil,
          assigned_die: map() | nil
        }

  @type t :: %__MODULE__{
          id: String.t(),
          name: String.t(),
          type: card_type(),
          damage: :intact | :damaged | :destroyed,
          properties: map(),
          dice_slots: [dice_slot()],
          last_result: map() | nil,
          current_hp: non_neg_integer() | nil
        }

  @enforce_keys [:id, :name, :type]
  defstruct [:id, :name, :type, damage: :intact, properties: %{}, dice_slots: [], last_result: nil, current_hp: nil]

  @spec meets_condition?(dice_condition() | nil, pos_integer()) :: boolean()
  def meets_condition?(nil, _value), do: true
  def meets_condition?({:min, min}, value), do: value >= min
  def meets_condition?({:max, max}, value), do: value <= max
  def meets_condition?({:exact, n}, value), do: value == n
  def meets_condition?(:even, value), do: rem(value, 2) == 0
  def meets_condition?(:odd, value), do: rem(value, 2) == 1

  @doc """
  Derives the damage state from the card's current HP relative to its max HP.
  Falls back to the static `damage` field if `current_hp` is not set.
  """
  @spec damage_state(t()) :: :intact | :damaged | :destroyed
  def damage_state(%__MODULE__{current_hp: nil} = card), do: card.damage
  def damage_state(%__MODULE__{current_hp: hp}) when hp <= 0, do: :destroyed

  def damage_state(%__MODULE__{current_hp: hp, properties: props}) do
    max_hp = Map.get(props, :card_hp, 2)
    if hp <= div(max_hp, 2), do: :damaged, else: :intact
  end

  @doc """
  Updates the card's `damage` field to match the derived damage state from HP.
  """
  @spec sync_damage_state(t()) :: t()
  def sync_damage_state(%__MODULE__{current_hp: nil} = card), do: card
  def sync_damage_state(%__MODULE__{} = card), do: %{card | damage: damage_state(card)}
end
