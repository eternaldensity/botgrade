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
      cpu("cpu_1", "Basic CPU", card_hp: 3)
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
      cpu("e_cpu_1", "Rogue CPU", card_hp: 3),
      locomotion("e_loc_1", "Rogue Treads", speed_base: 1, card_hp: 2)
    ]
  end

  @doc "Returns enemy cards for the given type string."
  def enemy_deck("ironclad"), do: enemy_ironclad()
  def enemy_deck("strikebolt"), do: enemy_strikebolt()
  def enemy_deck("hexapod"), do: enemy_hexapod()
  def enemy_deck(_), do: enemy_deck()

  @doc "Returns available enemy types as {id, name, description} tuples."
  def enemy_types do
    [
      {"rogue", "Rogue Bot", "A basic scavenger bot. Balanced and predictable."},
      {"ironclad", "Ironclad", "Heavy tank with massive armor and crushing kinetic weapons."},
      {"strikebolt", "Strikebolt", "Fast glass cannon with three weapons and fragile components."},
      {"hexapod", "Hexapod", "Versatile six-legged bot with all three damage types."}
    ]
  end

  # --- Enemy: Ironclad (Heavy/Tank) ---
  # Total chassis HP: 14. Double plating, all kinetic. Counter with energy weapons.

  def enemy_ironclad do
    [
      battery("e_bat_1", "Ironclad Dynamo", dice_count: 1, die_sides: 6, max_activations: 5, card_hp: 3),
      battery("e_bat_2", "Ironclad Dynamo", dice_count: 1, die_sides: 6, max_activations: 5, card_hp: 3),
      weapon("e_wpn_1", "Siege Hammer",
        damage_base: 2,
        damage_type: :kinetic,
        slots: 2,
        card_hp: 4,
        targeting: %{chassis: 40, armor: 20, weapon: 15, battery: 10, locomotion: 10, capacitor: 3, cpu: 2}
      ),
      weapon("e_wpn_2", "Grinder Claw",
        damage_base: 1,
        damage_type: :kinetic,
        slots: 1,
        card_hp: 3,
        targeting: %{armor: 30, weapon: 20, chassis: 20, battery: 10, locomotion: 10, capacitor: 5, cpu: 5}
      ),
      armor("e_arm_1", "Ironclad Plate", shield_base: 1, armor_type: :plating, slots: 1, card_hp: 4),
      armor("e_arm_2", "Scrap Barrier", shield_base: 0, armor_type: :plating, slots: 1, card_hp: 3),
      chassis("e_chs_1", "Ironclad Core", card_hp: 5),
      chassis("e_chs_2", "Ironclad Frame", card_hp: 5),
      chassis("e_chs_3", "Reinforced Plate", card_hp: 4),
      cpu("e_cpu_1", "Ironclad CPU", card_hp: 4, cpu_ability: %{type: :reflex_block}),
      locomotion("e_loc_1", "Heavy Treads", speed_base: 1, card_hp: 3)
    ]
  end

  # --- Enemy: Strikebolt (Fast/Glass Cannon) ---
  # Total chassis HP: 5. Three weapons, three batteries, everything fragile.

  def enemy_strikebolt do
    [
      battery("e_bat_1", "Strikebolt Cell", dice_count: 2, die_sides: 4, max_activations: 4, card_hp: 1),
      battery("e_bat_2", "Strikebolt Cell", dice_count: 1, die_sides: 6, max_activations: 4, card_hp: 1),
      battery("e_bat_3", "Overcharge Pack", dice_count: 1, die_sides: 6, max_activations: 3, card_hp: 1),
      weapon("e_wpn_1", "Pulse Blaster",
        damage_base: 0,
        damage_type: :energy,
        slots: 1,
        card_hp: 2,
        targeting: %{battery: 30, weapon: 20, capacitor: 15, armor: 10, cpu: 10, chassis: 10, locomotion: 5}
      ),
      weapon("e_wpn_2", "Spike Launcher",
        damage_base: 1,
        damage_type: :kinetic,
        slots: 1,
        card_hp: 2,
        targeting: %{weapon: 25, battery: 20, armor: 15, chassis: 15, capacitor: 10, cpu: 10, locomotion: 5}
      ),
      weapon("e_wpn_3", "Feedback Loop",
        damage_base: 1,
        damage_type: :energy,
        slots: 1,
        card_hp: 2,
        dual_mode: %{condition: {:max, 2}, armor_type: :shield, shield_base: 2},
        targeting: %{battery: 25, capacitor: 20, cpu: 15, weapon: 15, armor: 10, chassis: 10, locomotion: 5}
      ),
      armor("e_arm_1", "Flicker Shield",
        shield_base: 1,
        armor_type: :shield,
        slots: 1,
        card_hp: 1,
        condition: {:min, 4}
      ),
      chassis("e_chs_1", "Strikebolt Frame", card_hp: 3),
      chassis("e_chs_2", "Light Frame", card_hp: 2),
      cpu("e_cpu_1", "Strikebolt CPU", card_hp: 2, cpu_ability: %{type: :target_lock, requires_card_name: "Strikebolt Cell"}),
      locomotion("e_loc_1", "Sprint Jets", speed_base: 3, card_hp: 1)
    ]
  end

  # --- Enemy: Hexapod (Balanced/Versatile) ---
  # Total chassis HP: 9. All three damage types, mixed defenses.

  def enemy_hexapod do
    [
      battery("e_bat_1", "Hexapod Reactor", dice_count: 2, die_sides: 6, max_activations: 4, card_hp: 2),
      battery("e_bat_2", "Aux Cell", dice_count: 1, die_sides: 4, max_activations: 5, card_hp: 2),
      weapon("e_wpn_1", "Plasma Arc Generator",
        damage_base: 0,
        damage_type: :plasma,
        slots: 1,
        card_hp: 3,
        dual_mode: %{condition: :odd, armor_type: :shield, shield_base: 1},
        targeting: %{chassis: 30, weapon: 20, armor: 15, battery: 15, cpu: 10, capacitor: 5, locomotion: 5}
      ),
      weapon("e_wpn_2", "Pincer Strike",
        damage_base: 1,
        damage_type: :kinetic,
        slots: 1,
        card_hp: 3,
        targeting: %{armor: 25, chassis: 20, weapon: 20, battery: 15, locomotion: 10, capacitor: 5, cpu: 5}
      ),
      weapon("e_wpn_3", "Beam Array",
        damage_base: 0,
        damage_type: :energy,
        slots: 1,
        card_hp: 2,
        condition: {:min, 4},
        targeting: %{battery: 25, capacitor: 20, cpu: 20, weapon: 15, armor: 10, chassis: 5, locomotion: 5}
      ),
      armor("e_arm_1", "Chitin Plating", shield_base: 0, armor_type: :plating, slots: 1, card_hp: 3),
      armor("e_arm_2", "Refraction Field",
        shield_base: 1,
        armor_type: :shield,
        slots: 1,
        card_hp: 2,
        condition: :odd
      ),
      chassis("e_chs_1", "Hexapod Core", card_hp: 4),
      chassis("e_chs_2", "Hexapod Segment", card_hp: 3),
      chassis("e_chs_3", "Leg Segment", card_hp: 2),
      cpu("e_cpu_1", "Hexapod Brain", card_hp: 3, cpu_ability: %{type: :overclock_battery}),
      locomotion("e_loc_1", "Six Legs", speed_base: 2, card_hp: 2)
    ]
  end

  # --- Expanded Card Pool (for future deck-building/shop features) ---

  def expanded_card_pool do
    [
      weapon("wpn_plasma_cutter", "Plasma Cutter",
        damage_base: 0,
        damage_type: :plasma,
        slots: 1,
        card_hp: 2,
        condition: :odd,
        targeting: %{chassis: 35, weapon: 20, armor: 15, battery: 10, capacitor: 5, locomotion: 10, cpu: 5}
      ),
      weapon("wpn_twin_repeater", "Twin Repeater",
        damage_base: 0,
        damage_type: :kinetic,
        slots: 2,
        card_hp: 3,
        targeting: %{armor: 30, chassis: 20, weapon: 15, battery: 15, locomotion: 10, capacitor: 5, cpu: 5}
      ),
      weapon("wpn_precision_laser", "Precision Laser",
        damage_base: 2,
        damage_type: :energy,
        slots: 1,
        card_hp: 2,
        condition: {:min, 5},
        targeting: %{cpu: 35, battery: 25, capacitor: 20, weapon: 10, armor: 5, chassis: 3, locomotion: 2}
      ),
      battery("bat_surge", "Surge Cell", dice_count: 3, die_sides: 4, max_activations: 3, card_hp: 2),
      battery("bat_heavy_reactor", "Heavy Reactor", dice_count: 1, die_sides: 8, max_activations: 3, card_hp: 4),
      capacitor("cap_flux", "Flux Capacitor", max_stored: 3, card_hp: 3),
      armor("arm_reactive_plating", "Reactive Plating",
        shield_base: 1,
        armor_type: :plating,
        slots: 2,
        card_hp: 4
      ),
      armor("arm_phase_shield", "Phase Shield",
        shield_base: 2,
        armor_type: :shield,
        slots: 1,
        card_hp: 2,
        condition: :even
      ),
      weapon("wpn_stub_gun", "Stub Gun",
        damage_base: 3,
        damage_type: :kinetic,
        slots: 1,
        card_hp: 2,
        condition: {:max, 2},
        targeting: %{weapon: 20, armor: 15, battery: 15, chassis: 20, locomotion: 10, capacitor: 10, cpu: 10}
      ),
      weapon("wpn_plasma_arc", "Plasma Arc Generator",
        damage_base: 0,
        damage_type: :plasma,
        slots: 1,
        card_hp: 3,
        dual_mode: %{condition: :odd, armor_type: :shield, shield_base: 1},
        targeting: %{chassis: 30, weapon: 20, armor: 15, battery: 15, cpu: 10, capacitor: 5, locomotion: 5}
      ),
      weapon("wpn_feedback_loop", "Feedback Loop",
        damage_base: 1,
        damage_type: :energy,
        slots: 1,
        card_hp: 2,
        dual_mode: %{condition: {:max, 2}, armor_type: :shield, shield_base: 2},
        targeting: %{battery: 25, capacitor: 20, cpu: 15, weapon: 15, armor: 10, chassis: 10, locomotion: 5}
      ),
      capacitor("cap_overclocked", "Overclocked Capacitor", max_stored: 4, card_hp: 2),
      battery("bat_micro_cell", "Micro Cell", dice_count: 1, die_sides: 4, max_activations: 8, card_hp: 1),
      cpu("cpu_reflex", "Reflex Processor", card_hp: 2, cpu_ability: %{type: :reflex_block}),
      cpu("cpu_target_lock", "Targeting Computer", card_hp: 2, cpu_ability: %{type: :target_lock}),
      cpu("cpu_overclock", "Overclock Module", card_hp: 2, cpu_ability: %{type: :overclock_battery}),
      cpu("cpu_siphon", "Siphon Core", card_hp: 3, cpu_ability: %{type: :siphon_power}),
      # --- New Cards ---
      weapon("wpn_kinetic_laser", "Kinetic Laser",
        damage_base: 1,
        damage_type: :kinetic,
        slots: 1,
        card_hp: 2,
        condition: {:max, 3},
        max_activations_per_turn: 3,
        targeting: %{weapon: 20, armor: 15, battery: 15, chassis: 15, locomotion: 15, capacitor: 10, cpu: 10}
      ),
      weapon("wpn_boxing_glove", "Boxing Glove",
        damage_base: -2,
        damage_type: :kinetic,
        slots: 1,
        card_hp: 3,
        condition: {:min, 2},
        max_activations_per_turn: 2,
        targeting: %{chassis: 25, armor: 20, weapon: 20, battery: 15, locomotion: 10, capacitor: 5, cpu: 5}
      ),
      weapon("wpn_nova_cannon", "Nova Cannon",
        damage_base: 0,
        damage_type: :plasma,
        slots: 1,
        card_hp: 3,
        damage_multiplier: 2,
        self_damage: 1,
        targeting: %{chassis: 30, weapon: 20, armor: 15, battery: 15, cpu: 10, capacitor: 5, locomotion: 5}
      ),
      weapon("wpn_arc_projector", "Arc Projector",
        damage_base: 0,
        damage_type: :energy,
        slots: 1,
        card_hp: 2,
        escalating: true,
        targeting: %{battery: 25, capacitor: 20, weapon: 20, cpu: 15, armor: 10, chassis: 5, locomotion: 5}
      ),
      cpu("cpu_beam_splitter", "Beam Splitter", card_hp: 2, cpu_ability: %{type: :beam_split}, max_activations_per_turn: 2),
      cpu("cpu_overcharge", "Overcharge Module", card_hp: 2, cpu_ability: %{type: :overcharge}),
      cpu("cpu_extra_activation", "Boost Processor", card_hp: 2, cpu_ability: %{type: :extra_activation})
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

    properties =
      %{
        damage_base: Keyword.fetch!(opts, :damage_base),
        damage_type: Keyword.fetch!(opts, :damage_type),
        card_hp: Keyword.get(opts, :card_hp, 3),
        targeting_profile: Keyword.get(opts, :targeting, nil)
      }
      |> maybe_put(:dual_mode, Keyword.get(opts, :dual_mode))
      |> maybe_put(:max_activations_per_turn, Keyword.get(opts, :max_activations_per_turn))
      |> maybe_put(:damage_multiplier, Keyword.get(opts, :damage_multiplier))
      |> maybe_put(:self_damage, Keyword.get(opts, :self_damage))
      |> maybe_put(:escalating, Keyword.get(opts, :escalating))

    %Card{
      id: id,
      name: name,
      type: :weapon,
      properties: properties,
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
    properties =
      %{
        card_hp: Keyword.get(opts, :card_hp, 2),
        cpu_ability: Keyword.get(opts, :cpu_ability, %{type: :discard_draw, discard_count: 2, draw_count: 1})
      }
      |> maybe_put(:max_activations_per_turn, Keyword.get(opts, :max_activations_per_turn))

    %Card{
      id: id,
      name: name,
      type: :cpu,
      properties: properties,
      dice_slots: []
    }
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)
end
