defmodule Botgrade.Combat.CombatSupervisor do
  use Supervisor

  def start_link(init_arg) do
    Supervisor.start_link(__MODULE__, init_arg, name: __MODULE__)
  end

  @impl true
  def init(_init_arg) do
    children = [
      {Registry, keys: :unique, name: Botgrade.Combat.Registry},
      {DynamicSupervisor, name: Botgrade.Combat.DynamicSupervisor, strategy: :one_for_one}
    ]

    Supervisor.init(children, strategy: :one_for_all)
  end

  def start_combat(combat_id) do
    DynamicSupervisor.start_child(
      Botgrade.Combat.DynamicSupervisor,
      {Botgrade.Combat.CombatServer, combat_id: combat_id}
    )
  end
end
