defmodule Botgrade.Game.CombatLogicTest do
  use ExUnit.Case, async: true

  alias Botgrade.Game.{CombatLogic, CombatState, Card, Robot, StarterDecks}

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
      assert Robot.total_hp(state.player) == 12
      assert Robot.current_hp(state.player) == 12
      assert Robot.total_hp(state.enemy) == 9
      assert Robot.current_hp(state.enemy) == 9
    end

    test "player deck has 9 non-installed cards" do
      state = new_combat()
      assert length(state.player.deck) == 9
    end

    test "enemy deck has 5 non-installed cards" do
      state = new_combat()
      assert length(state.enemy.deck) == 5
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
      assert length(state.player.deck) == 4
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
          installed: [%Card{id: "chs", name: "Frame", type: :chassis, properties: %{card_hp: 9}, dice_slots: [], current_hp: 9}]
        },
        enemy: %Botgrade.Game.Robot{
          id: "enemy",
          name: "Enemy",
          installed: [%Card{id: "chs", name: "Frame", type: :chassis, properties: %{card_hp: 9}, dice_slots: [], current_hp: 9}]
        },
        phase: :power_up
      }

      %{state: state}
    end

    test "assigns die to an empty slot and triggers immediate activation", %{state: state} do
      {:ok, new_state} = CombatLogic.allocate_die(state, 0, "wpn_test", "power_1")
      # Weapon has 1 slot, so filling it triggers immediate activation
      # Card stays in hand with activated_this_turn flag set
      assert Robot.current_hp(new_state.enemy) == 4
      assert length(new_state.player.available_dice) == 1
      card = Enum.find(new_state.player.hand, &(&1.id == "wpn_test"))
      assert card != nil
      assert Map.get(card.properties, :activated_this_turn, false) == true
      assert card.dice_slots |> Enum.all?(&is_nil(&1.assigned_die))
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
          installed: [%Card{id: "chs", name: "Frame", type: :chassis, properties: %{card_hp: 9}, dice_slots: [], current_hp: 9}]
        },
        enemy: %Botgrade.Game.Robot{
          id: "enemy",
          name: "Enemy",
          installed: [%Card{id: "chs", name: "Frame", type: :chassis, properties: %{card_hp: 9}, dice_slots: [], current_hp: 9}]
        },
        phase: :power_up
      }

      {:ok, new_state} = CombatLogic.allocate_die(state, 0, "wpn_test", "power_1")
      # damage = die value 4 + base 1 = 5
      assert Robot.current_hp(new_state.enemy) == 4
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
          installed: [%Card{id: "chs", name: "Frame", type: :chassis, properties: %{card_hp: 9}, dice_slots: [], current_hp: 9}],
          plating: 0
        },
        enemy: %Botgrade.Game.Robot{
          id: "enemy",
          name: "Enemy",
          installed: [%Card{id: "chs", name: "Frame", type: :chassis, properties: %{card_hp: 9}, dice_slots: [], current_hp: 9}]
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
          installed: [%Card{id: "chs", name: "Frame", type: :chassis, properties: %{card_hp: 9}, dice_slots: [], current_hp: 9}]
        },
        enemy: %Botgrade.Game.Robot{
          id: "enemy",
          name: "Enemy",
          installed: [%Card{id: "chs", name: "Frame", type: :chassis, properties: %{card_hp: 9}, dice_slots: [], current_hp: 9}]
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
          installed: [%Card{id: "chs", name: "Frame", type: :chassis, properties: %{card_hp: 9}, dice_slots: [], current_hp: 9}]
        },
        enemy: %Botgrade.Game.Robot{
          id: "enemy",
          name: "Enemy",
          installed: [%Card{id: "chs", name: "Frame", type: :chassis, properties: %{card_hp: 5}, dice_slots: [], current_hp: 5}]
        },
        phase: :power_up
      }

      {:ok, new_state} = CombatLogic.allocate_die(state, 0, "wpn_test", "power_1")
      assert Robot.current_hp(new_state.enemy) == 0
      # Victory is checked during end_turn, not during immediate activation
      # The weapon fires and deals damage but the game continues in power_up
      # until end_turn is called
    end
  end

  describe "activation guard" do
    test "rejects die allocation to an already-activated weapon" do
      weapon = %Card{
        id: "wpn_used",
        name: "Used Weapon",
        type: :weapon,
        properties: %{damage_base: 0, damage_type: :energy, activated_this_turn: true},
        dice_slots: [%{id: "power_1", condition: nil, assigned_die: nil}]
      }

      state = %CombatState{
        id: "test",
        player: %Robot{
          id: "player",
          name: "Player",
          hand: [weapon],
          available_dice: [%{sides: 6, value: 5}],
          installed: [%Card{id: "chs", name: "Frame", type: :chassis, properties: %{card_hp: 9}, dice_slots: [], current_hp: 9}]
        },
        enemy: %Robot{
          id: "enemy",
          name: "Enemy",
          installed: [%Card{id: "chs", name: "Frame", type: :chassis, properties: %{card_hp: 9}, dice_slots: [], current_hp: 9}]
        },
        phase: :power_up
      }

      assert {:error, "Card already activated this turn."} =
               CombatLogic.allocate_die(state, 0, "wpn_used", "power_1")
    end

    test "rejects die allocation to an already-activated armor" do
      armor = %Card{
        id: "arm_used",
        name: "Used Armor",
        type: :armor,
        properties: %{shield_base: 1, armor_type: :shield, activated_this_turn: true},
        dice_slots: [%{id: "power_1", condition: nil, assigned_die: nil}]
      }

      state = %CombatState{
        id: "test",
        player: %Robot{
          id: "player",
          name: "Player",
          hand: [armor],
          available_dice: [%{sides: 6, value: 5}],
          installed: [%Card{id: "chs", name: "Frame", type: :chassis, properties: %{card_hp: 9}, dice_slots: [], current_hp: 9}]
        },
        enemy: %Robot{
          id: "enemy",
          name: "Enemy",
          installed: [%Card{id: "chs", name: "Frame", type: :chassis, properties: %{card_hp: 9}, dice_slots: [], current_hp: 9}]
        },
        phase: :power_up
      }

      assert {:error, "Card already activated this turn."} =
               CombatLogic.allocate_die(state, 0, "arm_used", "power_1")
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
          installed: [%Card{id: "chs", name: "Frame", type: :chassis, properties: %{card_hp: 9}, dice_slots: [], current_hp: 9}]
        },
        enemy: %Botgrade.Game.Robot{
          id: "enemy",
          name: "Enemy",
          installed: [%Card{id: "chs", name: "Frame", type: :chassis, properties: %{card_hp: 9}, dice_slots: [], current_hp: 9}],
          plating: 2,
          shield: 1
        },
        phase: :power_up
      }

      {:ok, new_state} = CombatLogic.allocate_die(state, 0, "wpn_test", "power_1")
      # 6 energy damage: plating absorbs 0.25*2=0, shield absorbs 1, 5 to HP
      assert new_state.enemy.plating == 2
      assert new_state.enemy.shield == 0
      assert Robot.current_hp(new_state.enemy) == 4
    end

    test "shield persists through end of turn and resets at start of next turn" do
      state = %CombatState{
        id: "test",
        player: %Botgrade.Game.Robot{
          id: "player",
          name: "Player",
          hand: [],
          installed: [%Card{id: "chs", name: "Frame", type: :chassis, properties: %{card_hp: 9}, dice_slots: [], current_hp: 9}],
          plating: 5,
          shield: 3
        },
        enemy: %Botgrade.Game.Robot{
          id: "enemy",
          name: "Enemy",
          installed: [%Card{id: "chs", name: "Frame", type: :chassis, properties: %{card_hp: 9}, dice_slots: [], current_hp: 9}]
        },
        phase: :power_up
      }

      new_state = CombatLogic.end_turn(state)
      # Shield persists after end_turn so it protects during enemy attacks
      assert new_state.player.shield == 3
      assert new_state.player.plating == 5

      # Shield resets at start of next player turn (draw phase)
      draw_state = %{new_state | phase: :draw, turn_owner: :player}
      next_turn_state = CombatLogic.draw_phase(draw_state)
      assert next_turn_state.player.shield == 0
      assert next_turn_state.player.plating == 5
    end
  end

  describe "enemy deck variants" do
    test "ironclad deck produces valid combat state" do
      state = CombatLogic.new_combat("test", StarterDecks.player_deck(), StarterDecks.enemy_ironclad())
      assert state.result == :ongoing
      assert length(state.enemy.installed) > 0
      assert Enum.any?(state.enemy.installed, &(&1.type == :chassis))
    end

    test "strikebolt deck produces valid combat state" do
      state = CombatLogic.new_combat("test", StarterDecks.player_deck(), StarterDecks.enemy_strikebolt())
      assert state.result == :ongoing
      assert length(state.enemy.installed) > 0
      assert Enum.any?(state.enemy.installed, &(&1.type == :chassis))
    end

    test "hexapod deck produces valid combat state" do
      state = CombatLogic.new_combat("test", StarterDecks.player_deck(), StarterDecks.enemy_hexapod())
      assert state.result == :ongoing
      assert length(state.enemy.installed) > 0
      assert Enum.any?(state.enemy.installed, &(&1.type == :chassis))
    end

    test "enemy_deck/1 dispatches to correct deck" do
      assert StarterDecks.enemy_deck("ironclad") == StarterDecks.enemy_ironclad()
      assert StarterDecks.enemy_deck("strikebolt") == StarterDecks.enemy_strikebolt()
      assert StarterDecks.enemy_deck("hexapod") == StarterDecks.enemy_hexapod()
      assert StarterDecks.enemy_deck("unknown") == StarterDecks.enemy_deck()
    end

    test "expanded_card_pool returns 37 cards" do
      pool = StarterDecks.expanded_card_pool()
      assert length(pool) == 37
    end
  end

  describe "dual-mode weapons" do
    test "weapon generates shield when die meets dual_mode condition" do
      weapon = %Card{
        id: "wpn_dual",
        name: "Plasma Arc Generator",
        type: :weapon,
        properties: %{
          damage_base: 0,
          damage_type: :plasma,
          dual_mode: %{condition: :odd, armor_type: :shield, shield_base: 1}
        },
        dice_slots: [%{id: "power_1", condition: nil, assigned_die: nil}]
      }

      state = %CombatState{
        id: "test",
        player: %Robot{
          id: "player",
          name: "Player",
          hand: [weapon],
          available_dice: [%{sides: 6, value: 3}],
          installed: [%Card{id: "chs", name: "Frame", type: :chassis, properties: %{card_hp: 9}, dice_slots: [], current_hp: 9}]
        },
        enemy: %Robot{
          id: "enemy",
          name: "Enemy",
          installed: [%Card{id: "chs", name: "Frame", type: :chassis, properties: %{card_hp: 9}, dice_slots: [], current_hp: 9}]
        },
        phase: :power_up
      }

      {:ok, new_state} = CombatLogic.allocate_die(state, 0, "wpn_dual", "power_1")
      # Odd die (3) triggers shield mode: shield_base 1 + die 3 = 4 shield
      assert new_state.player.shield == 4
      # Enemy HP unchanged — no damage dealt
      assert Robot.current_hp(new_state.enemy) == 9
      # Card stays in hand with shield result and activated flag
      card = Enum.find(new_state.player.hand, &(&1.id == "wpn_dual"))
      assert card.last_result.type == :shield
      assert card.last_result.value == 4
      assert Map.get(card.properties, :activated_this_turn, false) == true
    end

    test "weapon deals damage when die does not meet dual_mode condition" do
      weapon = %Card{
        id: "wpn_dual",
        name: "Plasma Arc Generator",
        type: :weapon,
        properties: %{
          damage_base: 0,
          damage_type: :plasma,
          dual_mode: %{condition: :odd, armor_type: :shield, shield_base: 1}
        },
        dice_slots: [%{id: "power_1", condition: nil, assigned_die: nil}]
      }

      state = %CombatState{
        id: "test",
        player: %Robot{
          id: "player",
          name: "Player",
          hand: [weapon],
          available_dice: [%{sides: 6, value: 4}],
          installed: [%Card{id: "chs", name: "Frame", type: :chassis, properties: %{card_hp: 9}, dice_slots: [], current_hp: 9}]
        },
        enemy: %Robot{
          id: "enemy",
          name: "Enemy",
          installed: [%Card{id: "chs", name: "Frame", type: :chassis, properties: %{card_hp: 9}, dice_slots: [], current_hp: 9}]
        },
        phase: :power_up
      }

      {:ok, new_state} = CombatLogic.allocate_die(state, 0, "wpn_dual", "power_1")
      # Even die (4) triggers damage mode: plasma damage = 0 + 4 = 4
      # Plasma bypasses plating/shield but is halved vs chassis: floor(4 * 0.5) = 2
      assert Robot.current_hp(new_state.enemy) == 7
      assert new_state.player.shield == 0
      card = Enum.find(new_state.player.hand, &(&1.id == "wpn_dual"))
      assert card.last_result.type == :damage
      assert Map.get(card.properties, :activated_this_turn, false) == true
    end

    test "feedback loop generates shield with low die" do
      weapon = %Card{
        id: "wpn_fb",
        name: "Feedback Loop",
        type: :weapon,
        properties: %{
          damage_base: 1,
          damage_type: :energy,
          dual_mode: %{condition: {:max, 2}, armor_type: :shield, shield_base: 2}
        },
        dice_slots: [%{id: "power_1", condition: nil, assigned_die: nil}]
      }

      state = %CombatState{
        id: "test",
        player: %Robot{
          id: "player",
          name: "Player",
          hand: [weapon],
          available_dice: [%{sides: 6, value: 1}],
          installed: [%Card{id: "chs", name: "Frame", type: :chassis, properties: %{card_hp: 9}, dice_slots: [], current_hp: 9}]
        },
        enemy: %Robot{
          id: "enemy",
          name: "Enemy",
          installed: [%Card{id: "chs", name: "Frame", type: :chassis, properties: %{card_hp: 9}, dice_slots: [], current_hp: 9}]
        },
        phase: :power_up
      }

      {:ok, new_state} = CombatLogic.allocate_die(state, 0, "wpn_fb", "power_1")
      # Die 1 meets {:max, 2}: shield_base 2 + die 1 = 3 shield
      assert new_state.player.shield == 3
      assert Robot.current_hp(new_state.enemy) == 9
    end

    test "feedback loop deals damage with high die" do
      weapon = %Card{
        id: "wpn_fb",
        name: "Feedback Loop",
        type: :weapon,
        properties: %{
          damage_base: 1,
          damage_type: :energy,
          dual_mode: %{condition: {:max, 2}, armor_type: :shield, shield_base: 2}
        },
        dice_slots: [%{id: "power_1", condition: nil, assigned_die: nil}]
      }

      state = %CombatState{
        id: "test",
        player: %Robot{
          id: "player",
          name: "Player",
          hand: [weapon],
          available_dice: [%{sides: 6, value: 5}],
          installed: [%Card{id: "chs", name: "Frame", type: :chassis, properties: %{card_hp: 9}, dice_slots: [], current_hp: 9}]
        },
        enemy: %Robot{
          id: "enemy",
          name: "Enemy",
          installed: [%Card{id: "chs", name: "Frame", type: :chassis, properties: %{card_hp: 9}, dice_slots: [], current_hp: 9}]
        },
        phase: :power_up
      }

      {:ok, new_state} = CombatLogic.allocate_die(state, 0, "wpn_fb", "power_1")
      # Die 5 does NOT meet {:max, 2}: energy damage = 1 + 5 = 6
      assert Robot.current_hp(new_state.enemy) < 9
      assert new_state.player.shield == 0
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
          installed: [
            %Card{id: "p_chs", name: "Frame", type: :chassis, properties: %{card_hp: 9}, dice_slots: [], current_hp: 9},
            %Card{id: "p_loc", name: "Treads", type: :locomotion, properties: %{speed_base: 1, card_hp: 2}, dice_slots: [], current_hp: 2}
          ],
          deck: [
            %Card{id: "p_wpn", name: "Blaster", type: :weapon, properties: %{damage_base: 0, damage_type: :energy, card_hp: 3}, dice_slots: [%{id: "power_1", condition: nil, assigned_die: nil}], current_hp: 3}
          ]
        },
        enemy: %Botgrade.Game.Robot{
          id: "enemy",
          name: "Enemy",
          installed: [
            %Card{id: "e_chs", name: "Frame", type: :chassis, properties: %{card_hp: 9}, dice_slots: [], current_hp: 9},
            %Card{id: "e_loc", name: "Treads", type: :locomotion, properties: %{speed_base: 1, card_hp: 2}, dice_slots: [], current_hp: 2}
          ],
          deck: [
            %Card{id: "e_wpn", name: "Claw", type: :weapon, properties: %{damage_base: 1, damage_type: :kinetic, card_hp: 3}, dice_slots: [%{id: "power_1", condition: nil, assigned_die: nil}], current_hp: 3}
          ]
        },
        phase: :power_up
      }

      new_state = CombatLogic.end_turn(state)
      assert new_state.phase == :enemy_turn
    end
  end
end
