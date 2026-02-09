defmodule Botgrade.Game.ScavengeLogicTest do
  use ExUnit.Case, async: true

  alias Botgrade.Game.{ScavengeLogic, CombatState, Card, Robot}

  defp make_enemy_cards do
    [
      %Card{
        id: "e_wpn",
        name: "Claw",
        type: :weapon,
        properties: %{damage_base: 1, damage_type: :kinetic},
        dice_slots: [%{id: "p1", condition: nil, assigned_die: nil}]
      },
      %Card{
        id: "e_arm",
        name: "Plating",
        type: :armor,
        properties: %{shield_base: 1, armor_type: :plating},
        dice_slots: [%{id: "p1", condition: nil, assigned_die: nil}]
      },
      %Card{
        id: "e_bat",
        name: "Cell",
        type: :battery,
        properties: %{dice_count: 1, die_sides: 6, max_activations: 3, remaining_activations: 1},
        dice_slots: []
      },
      %Card{
        id: "e_chs",
        name: "Frame",
        type: :chassis,
        properties: %{hp_max: 5},
        dice_slots: []
      }
    ]
  end

  defp won_state do
    %CombatState{
      id: "test",
      player: %Robot{
        id: "p",
        name: "Player",
        deck: [%Card{id: "p_chs", name: "Player Frame", type: :chassis, properties: %{card_hp: 9}, dice_slots: []}],
        hand: [],
        discard: [],
        in_play: [],
        installed: [%Card{id: "p_chs_inst", name: "Player Frame", type: :chassis, properties: %{card_hp: 9}, dice_slots: [], current_hp: 5}]
      },
      enemy: %Robot{
        id: "e",
        name: "Enemy",
        deck: make_enemy_cards(),
        hand: [],
        discard: [],
        in_play: [],
        installed: [%Card{id: "e_chs_inst", name: "Enemy Frame", type: :chassis, properties: %{card_hp: 9}, dice_slots: [], current_hp: 0}]
      },
      result: :player_wins
    }
  end

  describe "begin_scavenge/1" do
    test "transitions to scavenging phase with loot" do
      state = ScavengeLogic.begin_scavenge(won_state())
      assert state.phase == :scavenging
      assert is_list(state.scavenge_loot)
      assert state.scavenge_selected == []
      assert state.scavenge_limit == 3
    end

    test "resets battery activations on loot cards" do
      state = ScavengeLogic.begin_scavenge(won_state())

      batteries =
        Enum.filter(state.scavenge_loot, &(&1.type == :battery))

      for bat <- batteries do
        assert bat.properties.remaining_activations == bat.properties.max_activations
        refute Map.get(bat.properties, :activated_this_turn, false)
      end
    end

    test "clears assigned dice on loot cards" do
      enemy_cards = [
        %Card{
          id: "e_wpn",
          name: "Claw",
          type: :weapon,
          properties: %{damage_base: 1, damage_type: :kinetic},
          dice_slots: [%{id: "p1", condition: nil, assigned_die: %{sides: 6, value: 3}}]
        }
      ]

      state = %{won_state() | enemy: %{won_state().enemy | deck: enemy_cards}}
      result = ScavengeLogic.begin_scavenge(state)

      for card <- result.scavenge_loot do
        for slot <- card.dice_slots do
          assert slot.assigned_die == nil
        end
      end
    end
  end

  describe "toggle_card/2" do
    test "selects a card" do
      state = %{won_state() | phase: :scavenging, scavenge_loot: make_enemy_cards(), scavenge_selected: []}
      {:ok, state} = ScavengeLogic.toggle_card(state, "e_wpn")
      assert "e_wpn" in state.scavenge_selected
    end

    test "deselects a previously selected card" do
      state = %{won_state() | phase: :scavenging, scavenge_loot: make_enemy_cards(), scavenge_selected: ["e_wpn"]}
      {:ok, state} = ScavengeLogic.toggle_card(state, "e_wpn")
      refute "e_wpn" in state.scavenge_selected
    end

    test "enforces scavenge limit" do
      state = %{
        won_state()
        | phase: :scavenging,
          scavenge_loot: make_enemy_cards(),
          scavenge_selected: ["e_wpn", "e_arm", "e_bat"],
          scavenge_limit: 3
      }

      assert {:error, _} = ScavengeLogic.toggle_card(state, "e_chs")
    end

    test "returns error for unknown card" do
      state = %{won_state() | phase: :scavenging, scavenge_loot: make_enemy_cards(), scavenge_selected: []}
      assert {:error, _} = ScavengeLogic.toggle_card(state, "nonexistent")
    end
  end

  describe "confirm_scavenge/1" do
    test "moves selected cards to player deck and transitions to ended" do
      state = %{won_state() | phase: :scavenging, scavenge_loot: make_enemy_cards(), scavenge_selected: ["e_wpn"]}
      new_state = ScavengeLogic.confirm_scavenge(state)
      assert new_state.phase == :ended
      # Player had 1 card in deck + 1 installed, now should have those + scavenged card
      assert length(new_state.player.deck) == 3
    end

    test "gives scavenged cards unique IDs" do
      state = %{won_state() | phase: :scavenging, scavenge_loot: make_enemy_cards(), scavenge_selected: ["e_wpn"]}
      new_state = ScavengeLogic.confirm_scavenge(state)

      scavenged =
        Enum.find(new_state.player.deck, fn card -> String.starts_with?(card.id, "scav_") end)

      assert scavenged != nil
    end

    test "confirms with no selection produces empty scavenge" do
      state = %{won_state() | phase: :scavenging, scavenge_loot: make_enemy_cards(), scavenge_selected: []}
      new_state = ScavengeLogic.confirm_scavenge(state)
      assert new_state.phase == :ended
      # Player deck should have original deck card + installed card
      assert length(new_state.player.deck) == 2
    end

    test "consolidates all player cards into deck" do
      player = %{won_state().player | deck: [], hand: [hd(make_enemy_cards())], discard: [], in_play: []}
      state = %{won_state() | player: player, phase: :scavenging, scavenge_loot: make_enemy_cards(), scavenge_selected: []}
      new_state = ScavengeLogic.confirm_scavenge(state)
      assert new_state.player.hand == []
      assert new_state.player.discard == []
      assert new_state.player.in_play == []
      # 1 hand card + 1 installed card consolidated into deck
      assert length(new_state.player.deck) == 2
    end
  end
end
