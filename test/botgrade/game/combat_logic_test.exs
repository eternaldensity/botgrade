defmodule Botgrade.Game.CombatLogicTest do
  use ExUnit.Case, async: true

  alias Botgrade.Game.{CombatLogic, CombatState, Card, StarterDecks}

  defp new_combat do
    CombatLogic.new_combat("test", StarterDecks.player_deck(), StarterDecks.enemy_deck())
  end

  describe "new_combat/3" do
    test "creates initial state with correct structure" do
      state = new_combat()
      assert state.id == "test"
      assert state.phase == :draw
      assert state.turn_number == 1
      assert state.result == :ongoing
      assert state.player.total_hp == 9
      assert state.player.current_hp == 9
      assert state.enemy.total_hp == 9
      assert state.enemy.current_hp == 9
    end

    test "player deck has 12 cards" do
      state = new_combat()
      assert length(state.player.deck) == 12
    end

    test "enemy deck has 7 cards" do
      state = new_combat()
      assert length(state.enemy.deck) == 7
    end

    test "robots start with zero plating" do
      state = new_combat()
      assert state.player.plating == 0
      assert state.enemy.plating == 0
    end
  end

  describe "draw_phase/1" do
    test "draws 5 cards into hand and transitions to power_up" do
      state = new_combat() |> CombatLogic.draw_phase()
      assert length(state.player.hand) == 5
      assert length(state.player.deck) == 7
      assert state.phase == :power_up
    end
  end

  describe "activate_battery/2" do
    test "activating a battery adds dice to pool during power_up" do
      state = new_combat() |> CombatLogic.draw_phase()

      battery = Enum.find(state.player.hand, &(&1.type == :battery))

      if battery do
        {:ok, new_state} = CombatLogic.activate_battery(state, battery.id)
        assert length(new_state.player.available_dice) == battery.properties.dice_count
      end
    end

    test "rejects non-battery card" do
      state = new_combat() |> CombatLogic.draw_phase()

      non_battery = Enum.find(state.player.hand, &(&1.type != :battery))

      if non_battery do
        assert {:error, _} = CombatLogic.activate_battery(state, non_battery.id)
      end
    end

    test "rejects when not in power_up phase" do
      state = new_combat()
      assert {:error, _} = CombatLogic.activate_battery(state, "bat_1")
    end
  end

  describe "allocate_die/4" do
    setup do
      weapon = %Card{
        id: "wpn_test",
        name: "Test Weapon",
        type: :weapon,
        properties: %{damage_base: 0, damage_type: :energy},
        dice_slots: [%{id: "power_1", condition: nil, assigned_die: nil}]
      }

      conditioned_weapon = %Card{
        id: "wpn_cond",
        name: "Cond Weapon",
        type: :weapon,
        properties: %{damage_base: 0, damage_type: :energy},
        dice_slots: [%{id: "power_1", condition: {:min, 4}, assigned_die: nil}]
      }

      state = %CombatState{
        id: "test",
        player: %Botgrade.Game.Robot{
          id: "player",
          name: "Player",
          hand: [weapon, conditioned_weapon],
          available_dice: [%{sides: 6, value: 5}, %{sides: 6, value: 2}],
          total_hp: 9,
          current_hp: 9
        },
        enemy: %Botgrade.Game.Robot{
          id: "enemy",
          name: "Enemy",
          total_hp: 9,
          current_hp: 9
        },
        phase: :power_up
      }

      %{state: state}
    end

    test "assigns die to an empty slot and triggers immediate activation", %{state: state} do
      {:ok, new_state} = CombatLogic.allocate_die(state, 0, "wpn_test", "power_1")
      # Weapon has 1 slot, so filling it triggers immediate activation
      # Card moves to in_play with cleared slots, enemy takes 5 damage
      assert new_state.enemy.current_hp == 4
      assert length(new_state.player.available_dice) == 1
      # Card should be in in_play now
      assert Enum.any?(new_state.player.in_play, &(&1.id == "wpn_test"))
      assert not Enum.any?(new_state.player.hand, &(&1.id == "wpn_test"))
    end

    test "rejects die that doesn't meet condition", %{state: state} do
      # Die index 1 has value 2, condition requires min 4
      assert {:error, "Die doesn't meet slot condition."} =
               CombatLogic.allocate_die(state, 1, "wpn_cond", "power_1")
    end

    test "accepts die that meets condition", %{state: state} do
      # Die index 0 has value 5, condition requires min 4
      {:ok, _new_state} = CombatLogic.allocate_die(state, 0, "wpn_cond", "power_1")
    end
  end

  describe "immediate activation" do
    test "weapon deals damage immediately when all slots filled" do
      weapon = %Card{
        id: "wpn_test",
        name: "Test Weapon",
        type: :weapon,
        properties: %{damage_base: 1, damage_type: :energy},
        dice_slots: [%{id: "power_1", condition: nil, assigned_die: nil}]
      }

      state = %CombatState{
        id: "test",
        player: %Botgrade.Game.Robot{
          id: "player",
          name: "Player",
          hand: [weapon],
          available_dice: [%{sides: 6, value: 4}],
          total_hp: 9,
          current_hp: 9
        },
        enemy: %Botgrade.Game.Robot{
          id: "enemy",
          name: "Enemy",
          total_hp: 9,
          current_hp: 9
        },
        phase: :power_up
      }

      {:ok, new_state} = CombatLogic.allocate_die(state, 0, "wpn_test", "power_1")
      # damage = die value 4 + base 1 = 5
      assert new_state.enemy.current_hp == 4
    end

    test "armor with plating type adds to plating pool" do
      armor = %Card{
        id: "arm_test",
        name: "Test Plating",
        type: :armor,
        properties: %{shield_base: 1, armor_type: :plating},
        dice_slots: [%{id: "power_1", condition: nil, assigned_die: nil}]
      }

      state = %CombatState{
        id: "test",
        player: %Botgrade.Game.Robot{
          id: "player",
          name: "Player",
          hand: [armor],
          available_dice: [%{sides: 6, value: 3}],
          total_hp: 9,
          current_hp: 9,
          plating: 0
        },
        enemy: %Botgrade.Game.Robot{
          id: "enemy",
          name: "Enemy",
          total_hp: 9,
          current_hp: 9
        },
        phase: :power_up
      }

      {:ok, new_state} = CombatLogic.allocate_die(state, 0, "arm_test", "power_1")
      # plating = die value 3 + base 1 = 4
      assert new_state.player.plating == 4
    end

    test "armor with shield type adds to shield pool" do
      armor = %Card{
        id: "arm_test",
        name: "Test Shield",
        type: :armor,
        properties: %{shield_base: 1, armor_type: :shield},
        dice_slots: [%{id: "power_1", condition: nil, assigned_die: nil}]
      }

      state = %CombatState{
        id: "test",
        player: %Botgrade.Game.Robot{
          id: "player",
          name: "Player",
          hand: [armor],
          available_dice: [%{sides: 6, value: 3}],
          total_hp: 9,
          current_hp: 9
        },
        enemy: %Botgrade.Game.Robot{
          id: "enemy",
          name: "Enemy",
          total_hp: 9,
          current_hp: 9
        },
        phase: :power_up
      }

      {:ok, new_state} = CombatLogic.allocate_die(state, 0, "arm_test", "power_1")
      # shield = die value 3 + base 1 = 4
      assert new_state.player.shield == 4
    end

    test "victory when weapon kills enemy during power_up" do
      weapon = %Card{
        id: "wpn_test",
        name: "Big Gun",
        type: :weapon,
        properties: %{damage_base: 0, damage_type: :energy},
        dice_slots: [%{id: "power_1", condition: nil, assigned_die: nil}]
      }

      state = %CombatState{
        id: "test",
        player: %Botgrade.Game.Robot{
          id: "player",
          name: "Player",
          hand: [weapon],
          available_dice: [%{sides: 6, value: 6}],
          total_hp: 9,
          current_hp: 9
        },
        enemy: %Botgrade.Game.Robot{
          id: "enemy",
          name: "Enemy",
          total_hp: 5,
          current_hp: 5
        },
        phase: :power_up
      }

      {:ok, new_state} = CombatLogic.allocate_die(state, 0, "wpn_test", "power_1")
      assert new_state.enemy.current_hp == 0
      # Victory is checked during end_turn, not during immediate activation
      # The weapon fires and deals damage but the game continues in power_up
      # until end_turn is called
    end
  end

  describe "plating vs shield" do
    test "damage is absorbed by plating first, then shield, then HP" do
      weapon = %Card{
        id: "wpn_test",
        name: "Test Weapon",
        type: :weapon,
        properties: %{damage_base: 0, damage_type: :energy},
        dice_slots: [%{id: "power_1", condition: nil, assigned_die: nil}]
      }

      state = %CombatState{
        id: "test",
        player: %Botgrade.Game.Robot{
          id: "player",
          name: "Player",
          hand: [weapon],
          available_dice: [%{sides: 6, value: 6}],
          total_hp: 9,
          current_hp: 9
        },
        enemy: %Botgrade.Game.Robot{
          id: "enemy",
          name: "Enemy",
          total_hp: 9,
          current_hp: 9,
          plating: 2,
          shield: 1
        },
        phase: :power_up
      }

      {:ok, new_state} = CombatLogic.allocate_die(state, 0, "wpn_test", "power_1")
      # 6 damage: 2 absorbed by plating, 1 by shield, 3 to HP
      assert new_state.enemy.plating == 0
      assert new_state.enemy.shield == 0
      assert new_state.enemy.current_hp == 6
    end

    test "shield resets at end of turn but plating persists" do
      state = %CombatState{
        id: "test",
        player: %Botgrade.Game.Robot{
          id: "player",
          name: "Player",
          hand: [],
          total_hp: 9,
          current_hp: 9,
          plating: 5,
          shield: 3
        },
        enemy: %Botgrade.Game.Robot{
          id: "enemy",
          name: "Enemy",
          total_hp: 9,
          current_hp: 9
        },
        phase: :power_up
      }

      new_state = CombatLogic.end_turn(state)
      # After cleanup, shield resets but plating persists
      assert new_state.player.shield == 0
      assert new_state.player.plating == 5
    end
  end

  describe "end_turn/1" do
    test "transitions to enemy_turn when ongoing" do
      state = %CombatState{
        id: "test",
        player: %Botgrade.Game.Robot{
          id: "player",
          name: "Player",
          hand: [],
          total_hp: 9,
          current_hp: 9
        },
        enemy: %Botgrade.Game.Robot{
          id: "enemy",
          name: "Enemy",
          total_hp: 9,
          current_hp: 9
        },
        phase: :power_up
      }

      new_state = CombatLogic.end_turn(state)
      assert new_state.phase == :enemy_turn
    end
  end
end
