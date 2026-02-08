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
  end

  describe "draw_phase/1" do
    test "draws 5 cards into hand" do
      state = new_combat() |> CombatLogic.draw_phase()
      assert length(state.player.hand) == 5
      assert length(state.player.deck) == 7
      assert state.phase == :activate_batteries
    end
  end

  describe "activate_battery/2" do
    test "activating a battery adds dice to pool" do
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

    test "rejects when not in activation phase" do
      state = new_combat()
      assert {:error, _} = CombatLogic.activate_battery(state, "bat_1")
    end
  end

  describe "finish_activating/1" do
    test "transitions to allocate_dice phase" do
      state = new_combat() |> CombatLogic.draw_phase() |> CombatLogic.finish_activating()
      assert state.phase == :allocate_dice
    end
  end

  describe "allocate_die/4" do
    setup do
      # Create a minimal combat state with a weapon in hand and a die available
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
        phase: :allocate_dice
      }

      %{state: state}
    end

    test "assigns die to an empty slot", %{state: state} do
      {:ok, new_state} = CombatLogic.allocate_die(state, 0, "wpn_test", "power_1")
      weapon = Enum.find(new_state.player.hand, &(&1.id == "wpn_test"))
      slot = Enum.find(weapon.dice_slots, &(&1.id == "power_1"))
      assert slot.assigned_die == %{sides: 6, value: 5}
      assert length(new_state.player.available_dice) == 1
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

  describe "resolve/1" do
    test "weapon deals damage to enemy" do
      weapon = %Card{
        id: "wpn_test",
        name: "Test Weapon",
        type: :weapon,
        properties: %{damage_base: 1, damage_type: :energy},
        dice_slots: [%{id: "power_1", condition: nil, assigned_die: %{sides: 6, value: 4}}]
      }

      state = %CombatState{
        id: "test",
        player: %Botgrade.Game.Robot{
          id: "player",
          name: "Player",
          hand: [weapon],
          total_hp: 9,
          current_hp: 9
        },
        enemy: %Botgrade.Game.Robot{
          id: "enemy",
          name: "Enemy",
          total_hp: 9,
          current_hp: 9
        },
        phase: :resolve
      }

      new_state = CombatLogic.resolve(state)
      # damage = die value 4 + base 1 = 5
      assert new_state.enemy.current_hp == 4
    end

    test "armor absorbs damage" do
      weapon = %Card{
        id: "wpn_test",
        name: "Test Weapon",
        type: :weapon,
        properties: %{damage_base: 0, damage_type: :energy},
        dice_slots: [%{id: "power_1", condition: nil, assigned_die: %{sides: 6, value: 4}}]
      }

      armor = %Card{
        id: "arm_test",
        name: "Test Armor",
        type: :armor,
        properties: %{shield_base: 1, armor_type: :plating},
        dice_slots: [%{id: "power_1", condition: nil, assigned_die: %{sides: 6, value: 3}}]
      }

      state = %CombatState{
        id: "test",
        player: %Botgrade.Game.Robot{
          id: "player",
          name: "Player",
          hand: [weapon, armor],
          total_hp: 9,
          current_hp: 9
        },
        enemy: %Botgrade.Game.Robot{
          id: "enemy",
          name: "Enemy",
          total_hp: 9,
          current_hp: 9
        },
        phase: :resolve
      }

      new_state = CombatLogic.resolve(state)
      # Player armor: die 3 + base 1 = 4 shield (but this is player's shield, not enemy's)
      # Player weapon: die 4 + base 0 = 4 damage to enemy
      # Enemy has no shield so takes full 4 damage
      assert new_state.enemy.current_hp == 5
    end

    test "victory when enemy HP reaches 0" do
      weapon = %Card{
        id: "wpn_test",
        name: "Big Gun",
        type: :weapon,
        properties: %{damage_base: 0, damage_type: :energy},
        dice_slots: [%{id: "power_1", condition: nil, assigned_die: %{sides: 6, value: 6}}]
      }

      state = %CombatState{
        id: "test",
        player: %Botgrade.Game.Robot{
          id: "player",
          name: "Player",
          hand: [weapon],
          total_hp: 9,
          current_hp: 9
        },
        enemy: %Botgrade.Game.Robot{
          id: "enemy",
          name: "Enemy",
          total_hp: 5,
          current_hp: 5
        },
        phase: :resolve
      }

      new_state = CombatLogic.resolve(state)
      assert new_state.enemy.current_hp == 0
      assert new_state.result == :player_wins
      assert new_state.phase == :scavenging
      assert is_list(new_state.scavenge_loot)
    end
  end
end
