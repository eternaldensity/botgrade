defmodule Botgrade.Combat.CombatServer do
  use GenServer

  alias Botgrade.Game.{CombatLogic, ScavengeLogic, StarterDecks}

  # --- Client API ---

  def start_link(opts) do
    combat_id = Keyword.fetch!(opts, :combat_id)
    GenServer.start_link(__MODULE__, opts, name: via(combat_id))
  end

  def get_state(combat_id), do: GenServer.call(via(combat_id), :get_state)

  def activate_battery(combat_id, card_id),
    do: GenServer.call(via(combat_id), {:activate_battery, card_id})

  def activate_cpu(combat_id, card_id),
    do: GenServer.call(via(combat_id), {:activate_cpu, card_id})

  def toggle_cpu_discard(combat_id, card_id),
    do: GenServer.call(via(combat_id), {:toggle_cpu_discard, card_id})

  def select_cpu_target_card(combat_id, card_id),
    do: GenServer.call(via(combat_id), {:select_cpu_target_card, card_id})

  def confirm_cpu_ability(combat_id),
    do: GenServer.call(via(combat_id), :confirm_cpu_ability)

  def cancel_cpu_ability(combat_id),
    do: GenServer.call(via(combat_id), :cancel_cpu_ability)

  def allocate_die(combat_id, die_index, card_id, slot_id),
    do: GenServer.call(via(combat_id), {:allocate_die, die_index, card_id, slot_id})

  def unallocate_die(combat_id, card_id, slot_id),
    do: GenServer.call(via(combat_id), {:unallocate_die, card_id, slot_id})

  def end_turn(combat_id),
    do: GenServer.call(via(combat_id), :end_turn)

  def toggle_scavenge_card(combat_id, card_id),
    do: GenServer.call(via(combat_id), {:toggle_scavenge_card, card_id})

  def confirm_scavenge(combat_id),
    do: GenServer.call(via(combat_id), :confirm_scavenge)

  # --- Callbacks ---

  @impl true
  def init(opts) do
    combat_id = Keyword.fetch!(opts, :combat_id)
    player_cards = Keyword.get(opts, :player_cards, StarterDecks.player_deck())
    enemy_cards = Keyword.get(opts, :enemy_cards, StarterDecks.enemy_deck())
    player_resources = Keyword.get(opts, :player_resources, %{})

    state =
      CombatLogic.new_combat(combat_id, player_cards, enemy_cards, player_resources)
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
  def handle_call({:activate_cpu, card_id}, _from, state) do
    case CombatLogic.activate_cpu(state, card_id) do
      {:ok, new_state} ->
        broadcast(new_state)
        {:reply, {:ok, new_state}, new_state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_call({:toggle_cpu_discard, card_id}, _from, state) do
    case CombatLogic.toggle_cpu_discard(state, card_id) do
      {:ok, new_state} ->
        broadcast(new_state)
        {:reply, {:ok, new_state}, new_state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_call({:select_cpu_target_card, card_id}, _from, state) do
    case CombatLogic.select_cpu_target_card(state, card_id) do
      {:ok, new_state} ->
        broadcast(new_state)
        {:reply, {:ok, new_state}, new_state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_call(:confirm_cpu_ability, _from, state) do
    case CombatLogic.confirm_cpu_ability(state) do
      {:ok, new_state} ->
        broadcast(new_state)
        {:reply, {:ok, new_state}, new_state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_call(:cancel_cpu_ability, _from, state) do
    case CombatLogic.cancel_cpu_ability(state) do
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
  def handle_call(:end_turn, _from, state) do
    new_state =
      state
      |> CombatLogic.end_turn()
      |> maybe_enemy_turn()
      |> maybe_draw_phase()

    broadcast(new_state)
    {:reply, {:ok, new_state}, new_state}
  end

  @impl true
  def handle_call({:toggle_scavenge_card, card_id}, _from, state) do
    case ScavengeLogic.toggle_card(state, card_id) do
      {:ok, new_state} ->
        broadcast(new_state)
        {:reply, {:ok, new_state}, new_state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_call(:confirm_scavenge, _from, state) do
    new_state = ScavengeLogic.confirm_scavenge(state)
    broadcast(new_state)
    {:reply, {:ok, new_state}, new_state}
  end

  # --- Private ---

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
