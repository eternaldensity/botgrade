defmodule Botgrade.Game.StarterDecks do
  alias Botgrade.Game.Card

  def player_deck do
    [
      battery("bat_1", "Small Battery", dice_count: 1, die_sides: 6, max_activations: 5, card_hp: 2),
      battery("bat_2", "Small Battery", dice_count: 1, die_sides: 6, max_activations: 5, card_hp: 2),
      battery("bat_3", "Medium Battery", dice_count: 2, die_sides: 4, max_activations: 4, card_hp: 3),
      capacitor("cap_1", "Basic Capacitor", max_stored: 2, card_hp: 2),
      weapon("wpn_1", "Arm Blaster",
        damage_base: 0,
        damage_type: :energy,
        slots: 1,
        card_hp: 3,
        targeting: %{weapon: 20, armor: 15, battery: 15, capacitor: 10, chassis: 15, locomotion: 15, cpu: 10}
      ),
      weapon("wpn_2", "Chassis Ram",
        damage_base: 1,
        damage_type: :kinetic,
        slots: 1,
        card_hp: 3,
        targeting: %{chassis: 40, armor: 20, locomotion: 15, weapon: 10, battery: 10, capacitor: 3, cpu: 2}
      ),
      armor("arm_1", "Plating", shield_base: 0, armor_type: :plating, slots: 1, card_hp: 3),
      armor("arm_2", "Energy Shield",
        shield_base: 1,
        armor_type: :shield,
        slots: 1,
        card_hp: 3,
        condition: {:min, 3}
      ),
      locomotion("loc_1", "Treads", speed_base: 1, card_hp: 2),
      chassis("chs_1", "Core Frame", card_hp: 5),
      chassis("chs_2", "Armor Plate", card_hp: 4),
      chassis("chs_3", "Aux Frame", card_hp: 2),
      cpu("cpu_1", "Basic CPU", card_hp: 2)
    ]
  end

  def enemy_deck do
    [
      battery("e_bat_1", "Rogue Battery", dice_count: 2, die_sides: 6, max_activations: 4, card_hp: 2),
      battery("e_bat_2", "Rogue Battery", dice_count: 1, die_sides: 6, max_activations: 5, card_hp: 2),
      weapon("e_wpn_1", "Claw",
        damage_base: 1,
        damage_type: :kinetic,
        slots: 1,
        card_hp: 3,
        targeting: %{weapon: 25, armor: 15, battery: 15, capacitor: 10, chassis: 20, locomotion: 10, cpu: 5}
      ),
      weapon("e_wpn_2", "Shock Emitter",
        damage_base: 0,
        damage_type: :energy,
        slots: 1,
        card_hp: 2,
        targeting: %{battery: 30, capacitor: 25, cpu: 20, weapon: 10, armor: 5, chassis: 5, locomotion: 5}
      ),
      armor("e_arm_1", "Scrap Plating", shield_base: 0, armor_type: :plating, slots: 1, card_hp: 2),
      chassis("e_chs_1", "Rogue Frame", card_hp: 5),
      chassis("e_chs_2", "Rogue Frame", card_hp: 4),
      cpu("e_cpu_1", "Rogue CPU", card_hp: 2),
      locomotion("e_loc_1", "Rogue Treads", speed_base: 1, card_hp: 2)
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
        remaining_activations: Keyword.fetch!(opts, :max_activations),
        card_hp: Keyword.get(opts, :card_hp, 2)
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
      properties: %{
        max_stored: max_stored,
        card_hp: Keyword.get(opts, :card_hp, 2)
      },
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
        damage_type: Keyword.fetch!(opts, :damage_type),
        card_hp: Keyword.get(opts, :card_hp, 3),
        targeting_profile: Keyword.get(opts, :targeting, nil)
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
        armor_type: Keyword.fetch!(opts, :armor_type),
        card_hp: Keyword.get(opts, :card_hp, 3)
      },
      dice_slots: slots
    }
  end

  defp locomotion(id, name, opts) do
    %Card{
      id: id,
      name: name,
      type: :locomotion,
      properties: %{
        speed_base: Keyword.fetch!(opts, :speed_base),
        card_hp: Keyword.get(opts, :card_hp, 2)
      },
      dice_slots: [%{id: "power_1", condition: nil, assigned_die: nil}]
    }
  end

  defp chassis(id, name, opts) do
    %Card{
      id: id,
      name: name,
      type: :chassis,
      properties: %{
        card_hp: Keyword.fetch!(opts, :card_hp)
      },
      dice_slots: []
    }
  end

  defp cpu(id, name, opts) do
    %Card{
      id: id,
      name: name,
      type: :cpu,
      properties: %{
        card_hp: Keyword.get(opts, :card_hp, 2)
      },
      dice_slots: []
    }
  end
end
