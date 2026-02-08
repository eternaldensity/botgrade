defmodule Botgrade.Combat.CombatServer do
  use GenServer

  alias Botgrade.Game.{CombatLogic, StarterDecks}

  # --- Client API ---

  def start_link(opts) do
    combat_id = Keyword.fetch!(opts, :combat_id)
    GenServer.start_link(__MODULE__, opts, name: via(combat_id))
  end

  def get_state(combat_id), do: GenServer.call(via(combat_id), :get_state)

  def activate_battery(combat_id, card_id),
    do: GenServer.call(via(combat_id), {:activate_battery, card_id})

  def finish_activating(combat_id),
    do: GenServer.call(via(combat_id), :finish_activating)

  def allocate_die(combat_id, die_index, card_id, slot_id),
    do: GenServer.call(via(combat_id), {:allocate_die, die_index, card_id, slot_id})

  def unallocate_die(combat_id, card_id, slot_id),
    do: GenServer.call(via(combat_id), {:unallocate_die, card_id, slot_id})

  def finish_allocating(combat_id),
    do: GenServer.call(via(combat_id), :finish_allocating)

  # --- Callbacks ---

  @impl true
  def init(opts) do
    combat_id = Keyword.fetch!(opts, :combat_id)

    state =
      CombatLogic.new_combat(combat_id, StarterDecks.player_deck(), StarterDecks.enemy_deck())
      |> CombatLogic.draw_phase()

    {:ok, state}
  end

  @impl true
  def handle_call(:get_state, _from, state) do
    {:reply, state, state}
  end

  @impl true
  def handle_call({:activate_battery, card_id}, _from, state) do
    case CombatLogic.activate_battery(state, card_id) do
      {:ok, new_state} ->
        broadcast(new_state)
        {:reply, {:ok, new_state}, new_state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_call({:allocate_die, die_index, card_id, slot_id}, _from, state) do
    case CombatLogic.allocate_die(state, die_index, card_id, slot_id) do
      {:ok, new_state} ->
        broadcast(new_state)
        {:reply, {:ok, new_state}, new_state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_call({:unallocate_die, card_id, slot_id}, _from, state) do
    case CombatLogic.unallocate_die(state, card_id, slot_id) do
      {:ok, new_state} ->
        broadcast(new_state)
        {:reply, {:ok, new_state}, new_state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_call(:finish_activating, _from, state) do
    new_state = CombatLogic.finish_activating(state)
    broadcast(new_state)
    {:reply, {:ok, new_state}, new_state}
  end

  @impl true
  def handle_call(:finish_allocating, _from, state) do
    new_state =
      state
      |> maybe_finish_activating()
      |> CombatLogic.finish_allocating()
      |> CombatLogic.resolve()
      |> maybe_enemy_turn()
      |> maybe_draw_phase()

    broadcast(new_state)
    {:reply, {:ok, new_state}, new_state}
  end

  # --- Private ---

  defp maybe_finish_activating(%{phase: :activate_batteries} = state) do
    CombatLogic.finish_activating(state)
  end

  defp maybe_finish_activating(state), do: state

  defp maybe_enemy_turn(%{result: :ongoing, phase: :enemy_turn} = state) do
    CombatLogic.enemy_turn(state)
  end

  defp maybe_enemy_turn(state), do: state

  defp maybe_draw_phase(%{result: :ongoing, phase: :draw} = state) do
    CombatLogic.draw_phase(state)
  end

  defp maybe_draw_phase(state), do: state

  defp broadcast(state) do
    Phoenix.PubSub.broadcast(Botgrade.PubSub, "combat:#{state.id}", {:state_updated, state})
  end

  defp via(combat_id) do
    {:via, Registry, {Botgrade.Combat.Registry, combat_id}}
  end
end
