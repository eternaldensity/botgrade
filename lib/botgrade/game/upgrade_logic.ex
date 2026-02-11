defmodule Botgrade.Game.UpgradeLogic do
  @moduledoc """
  Determines and applies upgrades for the Smithy location.
  Each card type has specific upgrade paths that make it more powerful.
  """

  alias Botgrade.Game.Card

  @type upgrade_info :: %{
          description: String.t(),
          cost: %{optional(atom()) => non_neg_integer()}
        }

  @upgrade_costs %{
    weapon: %{metal: 2, chips: 1},
    armor: %{metal: 2, plastic: 1},
    battery: %{wire: 2, chips: 1},
    capacitor: %{wire: 2, chips: 2},
    chassis: %{metal: 3},
    locomotion: %{metal: 1, grease: 1},
    cpu: %{chips: 3, wire: 1},
    utility: %{chips: 2, wire: 1}
  }

  @doc """
  Returns upgrade info (description + cost) for a card, or nil if not upgradeable.
  Damaged or destroyed cards cannot be upgraded.
  """
  @spec upgrade_info(Card.t()) :: upgrade_info() | nil
  def upgrade_info(%Card{damage: damage}) when damage != :intact, do: nil

  def upgrade_info(%Card{} = card) do
    desc = upgrade_description(card)
    cost = Map.get(@upgrade_costs, card.type, %{metal: 2})

    if desc do
      %{description: desc, cost: cost}
    else
      nil
    end
  end

  @doc """
  Applies the upgrade to a card. Returns the upgraded card.
  """
  @spec apply_upgrade(Card.t()) :: Card.t()
  def apply_upgrade(%Card{type: :weapon} = card) do
    cond do
      # Weapons with random_element upgrade to +1 activation per turn
      Map.get(card.properties, :random_element, false) ->
        update_prop(card, :max_activations_per_turn, &(&1 + 1))

      # First priority: relax a restrictive slot condition
      slot_to_relax(card) ->
        relax_slot_condition(card)

      # Second priority: +1 damage_base
      true ->
        update_prop(card, :damage_base, &(&1 + 1))
    end
  end

  def apply_upgrade(%Card{type: :armor} = card) do
    cond do
      slot_to_relax(card) ->
        relax_slot_condition(card)

      true ->
        update_prop(card, :shield_base, &(&1 + 1))
    end
  end

  def apply_upgrade(%Card{type: :battery} = card) do
    update_prop(card, :max_activations, &(&1 + 1))
  end

  def apply_upgrade(%Card{type: :capacitor} = card) do
    if Map.get(card.properties, :capacitor_ability) == :dynamo do
      update_prop(card, :boost_amount, &(&1 + 1))
    else
      new_max = Map.get(card.properties, :max_stored, 2) + 1
      new_slot = %{id: "store_#{new_max}", condition: nil, assigned_die: nil}

      card
      |> update_prop(:max_stored, &(&1 + 1))
      |> Map.update!(:dice_slots, &(&1 ++ [new_slot]))
    end
  end

  def apply_upgrade(%Card{type: :chassis} = card) do
    update_prop(card, :card_hp, &(&1 + 1))
  end

  def apply_upgrade(%Card{type: :locomotion} = card) do
    update_prop(card, :speed_base, &(&1 + 1))
  end

  def apply_upgrade(%Card{type: :cpu} = card) do
    update_prop(card, :card_hp, &(&1 + 1))
  end

  def apply_upgrade(%Card{type: :utility} = card) do
    ability = Map.get(card.properties, :utility_ability)

    cond do
      ability == :quantum_tumbler ->
        update_prop(card, :max_activations_per_turn, &(&1 + 1))

      ability == :internal_servo ->
        relax_slot_condition(card)

      slot_to_relax(card) ->
        relax_slot_condition(card)

      true ->
        update_prop(card, :card_hp, &(&1 + 1))
    end
  end

  def apply_upgrade(card), do: card

  # --- Descriptions ---

  defp upgrade_description(%Card{type: :weapon} = card) do
    cond do
      Map.get(card.properties, :random_element, false) ->
        acts = Map.get(card.properties, :max_activations_per_turn, 1)
        "+1 activation per turn (#{acts} -> #{acts + 1})"

      slot_to_relax(card) ->
        "Relax die restriction (easier to activate)"

      true ->
        base = Map.get(card.properties, :damage_base, 0)
        "+1 base damage (#{base} -> #{base + 1})"
    end
  end

  defp upgrade_description(%Card{type: :armor} = card) do
    if slot_to_relax(card) do
      "Relax die restriction (easier to activate)"
    else
      base = Map.get(card.properties, :shield_base, 0)
      "+1 base shield (#{base} -> #{base + 1})"
    end
  end

  defp upgrade_description(%Card{type: :battery} = card) do
    acts = Map.get(card.properties, :max_activations, 3)
    "+1 charge (#{acts} -> #{acts + 1})"
  end

  defp upgrade_description(%Card{type: :capacitor} = card) do
    if Map.get(card.properties, :capacitor_ability) == :dynamo do
      boost = Map.get(card.properties, :boost_amount, 1)
      "+1 boost per activation (+#{boost} -> +#{boost + 1})"
    else
      stored = Map.get(card.properties, :max_stored, 2)
      "+1 storage slot (#{stored} -> #{stored + 1})"
    end
  end

  defp upgrade_description(%Card{type: :chassis} = card) do
    hp = Map.get(card.properties, :card_hp, 2)
    "+1 HP (#{hp} -> #{hp + 1})"
  end

  defp upgrade_description(%Card{type: :locomotion} = card) do
    spd = Map.get(card.properties, :speed_base, 1)
    "+1 speed (#{spd} -> #{spd + 1})"
  end

  defp upgrade_description(%Card{type: :cpu} = card) do
    hp = Map.get(card.properties, :card_hp, 2)
    "+1 HP (#{hp} -> #{hp + 1})"
  end

  defp upgrade_description(%Card{type: :utility} = card) do
    ability = Map.get(card.properties, :utility_ability)

    cond do
      ability == :quantum_tumbler ->
        acts = Map.get(card.properties, :max_activations_per_turn, 2)
        "+1 activation per turn (#{acts} -> #{acts + 1})"

      ability == :internal_servo ->
        "Raise max die value requirement"

      slot_to_relax(card) ->
        "Relax die restriction (easier to activate)"

      true ->
        hp = Map.get(card.properties, :card_hp, 2)
        "+1 HP (#{hp} -> #{hp + 1})"
    end
  end

  defp upgrade_description(_), do: nil

  # --- Condition relaxation helpers ---

  defp slot_to_relax(%Card{dice_slots: slots}) do
    Enum.find(slots, fn slot -> relaxable_condition?(slot.condition) end)
  end

  defp relaxable_condition?({:min, n}) when n > 1, do: true
  defp relaxable_condition?({:max, n}) when n < 6, do: true
  defp relaxable_condition?({:exact, _}), do: true
  defp relaxable_condition?(_), do: false

  defp relax_slot_condition(card) do
    new_slots =
      Enum.map(card.dice_slots, fn slot ->
        if relaxable_condition?(slot.condition) do
          %{slot | condition: relax_condition(slot.condition)}
        else
          slot
        end
      end)

    %{card | dice_slots: new_slots}
  end

  defp relax_condition({:min, n}) when n > 1, do: {:min, n - 1}
  defp relax_condition({:max, n}) when n < 6, do: {:max, n + 1}
  defp relax_condition({:exact, n}), do: {:min, n}
  defp relax_condition(other), do: other

  # --- Property update helper ---

  defp update_prop(card, key, fun) do
    new_val = fun.(Map.get(card.properties, key, 0))
    %{card | properties: Map.put(card.properties, key, new_val)}
  end
end
