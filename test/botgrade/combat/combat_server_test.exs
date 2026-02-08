defmodule Botgrade.Combat.CombatServerTest do
  use ExUnit.Case

  alias Botgrade.Combat.{CombatServer, CombatSupervisor}

  setup do
    combat_id = "test_#{System.unique_integer([:positive])}"
    {:ok, _pid} = CombatSupervisor.start_combat(combat_id)
    %{combat_id: combat_id}
  end

  test "get_state returns initial combat state", %{combat_id: id} do
    state = CombatServer.get_state(id)
    assert state.id == id
    assert state.phase == :activate_batteries
    assert length(state.player.hand) == 5
    assert state.result == :ongoing
  end

  test "activate_battery adds dice to pool", %{combat_id: id} do
    state = CombatServer.get_state(id)
    battery = Enum.find(state.player.hand, &(&1.type == :battery))

    if battery do
      {:ok, new_state} = CombatServer.activate_battery(id, battery.id)
      assert length(new_state.player.available_dice) > 0
    end
  end

  test "full turn cycle works", %{combat_id: id} do
    state = CombatServer.get_state(id)

    # Activate any batteries in hand
    batteries = Enum.filter(state.player.hand, &(&1.type == :battery))

    for bat <- batteries do
      CombatServer.activate_battery(id, bat.id)
    end

    # Finish activating and resolve (which also runs enemy turn)
    {:ok, new_state} = CombatServer.finish_allocating(id)

    # Should be back to activate_batteries for next turn (or ended)
    assert new_state.phase in [:activate_batteries, :scavenging, :ended]

    if new_state.phase == :activate_batteries do
      assert new_state.turn_number == 2
    end
  end
end
