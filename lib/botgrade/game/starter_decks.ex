defmodule Botgrade.Game.StarterDecks do
  alias Botgrade.Game.Card

  def player_deck do
    [
      battery("bat_1", "Small Battery", dice_count: 1, die_sides: 6, max_activations: 5),
      battery("bat_2", "Small Battery", dice_count: 1, die_sides: 6, max_activations: 5),
      battery("bat_3", "Medium Battery", dice_count: 2, die_sides: 4, max_activations: 4),
      capacitor("cap_1", "Basic Capacitor", max_stored: 2),
      weapon("wpn_1", "Arm Blaster", damage_base: 0, damage_type: :energy, slots: 1),
      weapon("wpn_2", "Chassis Ram", damage_base: 1, damage_type: :kinetic, slots: 1),
      armor("arm_1", "Plating", shield_base: 0, armor_type: :plating, slots: 1),
      armor("arm_2", "Energy Shield",
        shield_base: 1,
        armor_type: :shield,
        slots: 1,
        condition: {:min, 3}
      ),
      locomotion("loc_1", "Treads", speed_base: 1),
      chassis("chs_1", "Core Frame", hp_max: 4),
      chassis("chs_2", "Armor Plate", hp_max: 3),
      chassis("chs_3", "Aux Frame", hp_max: 2)
    ]
  end

  def enemy_deck do
    [
      battery("e_bat_1", "Rogue Battery", dice_count: 2, die_sides: 6, max_activations: 4),
      battery("e_bat_2", "Rogue Battery", dice_count: 1, die_sides: 6, max_activations: 5),
      weapon("e_wpn_1", "Claw", damage_base: 1, damage_type: :kinetic, slots: 1),
      weapon("e_wpn_2", "Shock Emitter", damage_base: 0, damage_type: :energy, slots: 1),
      armor("e_arm_1", "Scrap Plating", shield_base: 0, armor_type: :plating, slots: 1),
      chassis("e_chs_1", "Rogue Frame", hp_max: 5),
      chassis("e_chs_2", "Rogue Frame", hp_max: 4)
    ]
  end

  defp battery(id, name, opts) do
    %Card{
      id: id,
      name: name,
      type: :battery,
      properties: %{
        dice_count: Keyword.fetch!(opts, :dice_count),
        die_sides: Keyword.fetch!(opts, :die_sides),
        max_activations: Keyword.fetch!(opts, :max_activations),
        remaining_activations: Keyword.fetch!(opts, :max_activations)
      },
      dice_slots: []
    }
  end

  defp capacitor(id, name, opts) do
    max_stored = Keyword.fetch!(opts, :max_stored)

    slots =
      Enum.map(1..max_stored, fn i ->
        %{id: "store_#{i}", condition: nil, assigned_die: nil}
      end)

    %Card{
      id: id,
      name: name,
      type: :capacitor,
      properties: %{max_stored: max_stored},
      dice_slots: slots
    }
  end

  defp weapon(id, name, opts) do
    slot_count = Keyword.get(opts, :slots, 1)

    slots =
      Enum.map(1..slot_count, fn i ->
        %{id: "power_#{i}", condition: Keyword.get(opts, :condition), assigned_die: nil}
      end)

    %Card{
      id: id,
      name: name,
      type: :weapon,
      properties: %{
        damage_base: Keyword.fetch!(opts, :damage_base),
        damage_type: Keyword.fetch!(opts, :damage_type)
      },
      dice_slots: slots
    }
  end

  defp armor(id, name, opts) do
    slot_count = Keyword.get(opts, :slots, 1)

    slots =
      Enum.map(1..slot_count, fn i ->
        %{id: "power_#{i}", condition: Keyword.get(opts, :condition), assigned_die: nil}
      end)

    %Card{
      id: id,
      name: name,
      type: :armor,
      properties: %{
        shield_base: Keyword.fetch!(opts, :shield_base),
        armor_type: Keyword.fetch!(opts, :armor_type)
      },
      dice_slots: slots
    }
  end

  defp locomotion(id, name, opts) do
    %Card{
      id: id,
      name: name,
      type: :locomotion,
      properties: %{speed_base: Keyword.fetch!(opts, :speed_base)},
      dice_slots: [%{id: "power_1", condition: nil, assigned_die: nil}]
    }
  end

  defp chassis(id, name, opts) do
    %Card{
      id: id,
      name: name,
      type: :chassis,
      properties: %{hp_max: Keyword.fetch!(opts, :hp_max)},
      dice_slots: []
    }
  end
end
