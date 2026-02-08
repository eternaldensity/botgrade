defmodule BotgradeWeb.CombatLive do
  use BotgradeWeb, :live_view

  alias Botgrade.Combat.{CombatServer, CombatSupervisor}

  @impl true
  def mount(%{"id" => combat_id}, _session, socket) do
    # Ensure combat exists, start if needed (handles page refresh)
    case Registry.lookup(Botgrade.Combat.Registry, combat_id) do
      [] -> CombatSupervisor.start_combat(combat_id)
      _ -> :ok
    end

    if connected?(socket) do
      Phoenix.PubSub.subscribe(Botgrade.PubSub, "combat:#{combat_id}")
    end

    state = CombatServer.get_state(combat_id)

    {:ok,
     assign(socket,
       combat_id: combat_id,
       state: state,
       selected_die: nil,
       error_message: nil
     )}
  end

  @impl true
  def handle_info({:state_updated, state}, socket) do
    {:noreply, assign(socket, state: state, error_message: nil)}
  end

  # --- Player Actions ---

  @impl true
  def handle_event("activate_battery", %{"card-id" => card_id}, socket) do
    case CombatServer.activate_battery(socket.assigns.combat_id, card_id) do
      {:ok, _state} -> {:noreply, assign(socket, error_message: nil)}
      {:error, reason} -> {:noreply, assign(socket, error_message: reason)}
    end
  end

  @impl true
  def handle_event("finish_batteries", _params, socket) do
    case CombatServer.finish_activating(socket.assigns.combat_id) do
      {:ok, _state} -> {:noreply, assign(socket, error_message: nil)}
      {:error, reason} -> {:noreply, assign(socket, error_message: reason)}
    end
  end

  @impl true
  def handle_event("select_die", %{"die-index" => idx}, socket) do
    index = String.to_integer(idx)

    selected =
      if socket.assigns.selected_die == index, do: nil, else: index

    {:noreply, assign(socket, selected_die: selected)}
  end

  @impl true
  def handle_event("assign_die", %{"card-id" => card_id, "slot-id" => slot_id}, socket) do
    case socket.assigns.selected_die do
      nil ->
        {:noreply, assign(socket, error_message: "Select a die first.")}

      die_index ->
        case CombatServer.allocate_die(
               socket.assigns.combat_id,
               die_index,
               card_id,
               slot_id
             ) do
          {:ok, _state} ->
            {:noreply, assign(socket, selected_die: nil, error_message: nil)}

          {:error, reason} ->
            {:noreply, assign(socket, error_message: reason)}
        end
    end
  end

  @impl true
  def handle_event("unassign_die", %{"card-id" => card_id, "slot-id" => slot_id}, socket) do
    case CombatServer.unallocate_die(socket.assigns.combat_id, card_id, slot_id) do
      {:ok, _state} -> {:noreply, assign(socket, error_message: nil)}
      {:error, reason} -> {:noreply, assign(socket, error_message: reason)}
    end
  end

  @impl true
  def handle_event("finish_allocating", _params, socket) do
    case CombatServer.finish_allocating(socket.assigns.combat_id) do
      {:ok, _state} -> {:noreply, assign(socket, selected_die: nil, error_message: nil)}
      {:error, reason} -> {:noreply, assign(socket, error_message: reason)}
    end
  end

  @impl true
  def handle_event("new_combat", _params, socket) do
    combat_id = Base.encode16(:crypto.strong_rand_bytes(4), case: :lower)
    {:ok, _pid} = CombatSupervisor.start_combat(combat_id)
    {:noreply, push_navigate(socket, to: ~p"/combat/#{combat_id}")}
  end

  # --- Render ---

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-screen bg-base-200 p-4">
      <div class="max-w-4xl mx-auto space-y-4">
        <%!-- Enemy Status --%>
        <.robot_status robot={@state.enemy} label="ENEMY" />

        <%!-- Combat Log --%>
        <div class="card bg-base-100 shadow-sm">
          <div class="card-body p-3">
            <h3 class="card-title text-sm">Combat Log</h3>
            <div class="h-32 overflow-y-auto text-xs font-mono space-y-0.5">
              <div :for={msg <- @state.log} class="text-base-content/70">
                {msg}
              </div>
            </div>
          </div>
        </div>

        <%!-- Error Message --%>
        <div :if={@error_message} class="alert alert-error text-sm">
          {@error_message}
        </div>

        <%!-- Victory/Defeat Overlay --%>
        <div :if={@state.result != :ongoing} class="card bg-base-100 shadow-lg">
          <div class="card-body text-center">
            <h2 class={[
              "text-3xl font-bold",
              @state.result == :player_wins && "text-success",
              @state.result == :enemy_wins && "text-error"
            ]}>
              {if @state.result == :player_wins, do: "VICTORY!", else: "DEFEAT"}
            </h2>
            <div class="card-actions justify-center mt-4">
              <button phx-click="new_combat" class="btn btn-primary">New Combat</button>
            </div>
          </div>
        </div>

        <%!-- Phase Controls & Dice Pool (only show during active combat) --%>
        <div :if={@state.result == :ongoing}>
          <%!-- Phase Indicator --%>
          <div class="flex items-center justify-between">
            <div class="badge badge-lg badge-primary">
              Turn {@state.turn_number} - {phase_label(@state.phase)}
            </div>

            <button
              :if={@state.phase == :activate_batteries}
              phx-click="finish_batteries"
              class="btn btn-sm btn-secondary"
            >
              Done Activating
            </button>

            <button
              :if={@state.phase == :allocate_dice}
              phx-click="finish_allocating"
              class="btn btn-sm btn-accent"
            >
              Resolve Turn
            </button>
          </div>

          <%!-- Dice Pool --%>
          <div :if={length(@state.player.available_dice) > 0 or @state.phase == :allocate_dice} class="card bg-base-100 shadow-sm">
            <div class="card-body p-3">
              <h3 class="card-title text-sm">Dice Pool</h3>
              <div class="flex flex-wrap gap-2">
                <button
                  :for={{die, idx} <- Enum.with_index(@state.player.available_dice)}
                  phx-click="select_die"
                  phx-value-die-index={idx}
                  class={[
                    "btn btn-sm font-mono",
                    @selected_die == idx && "btn-primary",
                    @selected_die != idx && "btn-outline"
                  ]}
                  disabled={@state.phase != :allocate_dice}
                >
                  {die.value} <span class="text-xs opacity-50">d{die.sides}</span>
                </button>
                <span :if={@state.player.available_dice == []} class="text-sm text-base-content/50">
                  No dice available
                </span>
              </div>
            </div>
          </div>
        </div>

        <%!-- Player Hand --%>
        <div class="card bg-base-100 shadow-sm">
          <div class="card-body p-3">
            <h3 class="card-title text-sm">Your Hand ({length(@state.player.hand)} cards)</h3>
            <div class="grid grid-cols-2 md:grid-cols-3 lg:grid-cols-4 gap-2">
              <.game_card
                :for={card <- @state.player.hand}
                card={card}
                phase={@state.phase}
                selected_die={@selected_die}
              />
            </div>
          </div>
        </div>

        <%!-- In Play Area --%>
        <div :if={@state.player.in_play != []} class="card bg-base-100 shadow-sm">
          <div class="card-body p-3">
            <h3 class="card-title text-sm">In Play</h3>
            <div class="grid grid-cols-2 md:grid-cols-3 lg:grid-cols-4 gap-2">
              <.game_card
                :for={card <- @state.player.in_play}
                card={card}
                phase={@state.phase}
                selected_die={@selected_die}
              />
            </div>
          </div>
        </div>

        <%!-- Player Status --%>
        <.robot_status robot={@state.player} label="YOU" />
      </div>
    </div>
    """
  end

  # --- Function Components ---

  defp robot_status(assigns) do
    ~H"""
    <div class="card bg-base-100 shadow-sm">
      <div class="card-body p-3 flex flex-row items-center gap-4">
        <span class="font-bold text-sm w-16">{@label}</span>
        <div class="flex-1">
          <div class="flex justify-between text-xs mb-1">
            <span>{@robot.name}</span>
            <span>{@robot.current_hp}/{@robot.total_hp} HP</span>
          </div>
          <progress
            class={[
              "progress w-full",
              hp_color(@robot.current_hp, @robot.total_hp)
            ]}
            value={@robot.current_hp}
            max={@robot.total_hp}
          />
        </div>
        <div :if={@robot.shield > 0} class="badge badge-info badge-sm">
          Shield: {@robot.shield}
        </div>
      </div>
    </div>
    """
  end

  defp game_card(assigns) do
    ~H"""
    <div class={[
      "border rounded-lg p-2 text-xs",
      card_border_color(@card.type),
      @card.type == :battery and @phase == :activate_batteries and "cursor-pointer hover:ring-2 ring-primary"
    ]}>
      <div class="flex justify-between items-start mb-1">
        <span class="font-bold">{@card.name}</span>
        <span class={["badge badge-xs", card_badge(@card.type)]}>
          {card_type_label(@card.type)}
        </span>
      </div>

      <%!-- Card-specific info --%>
      <div class="text-base-content/60 mb-1">
        <.card_info card={@card} />
      </div>

      <%!-- Battery activation button --%>
      <button
        :if={@card.type == :battery and @phase == :activate_batteries and @card.properties.remaining_activations > 0}
        phx-click="activate_battery"
        phx-value-card-id={@card.id}
        class="btn btn-xs btn-primary w-full mt-1"
      >
        Activate ({@card.properties.remaining_activations} left)
      </button>

      <%!-- Dice slots --%>
      <div :if={@card.dice_slots != []} class="mt-1 space-y-1">
        <div :for={slot <- @card.dice_slots} class="flex items-center gap-1">
          <span :if={slot.assigned_die} class="badge badge-sm badge-success font-mono">
            {slot.assigned_die.value}
          </span>
          <button
            :if={slot.assigned_die == nil and @phase == :allocate_dice and @selected_die != nil}
            phx-click="assign_die"
            phx-value-card-id={@card.id}
            phx-value-slot-id={slot.id}
            class="btn btn-xs btn-outline btn-primary"
          >
            Assign
            <span :if={slot.condition} class="text-warning">
              ({condition_label(slot.condition)})
            </span>
          </button>
          <span :if={slot.assigned_die == nil and (@phase != :allocate_dice or @selected_die == nil)} class="badge badge-sm badge-ghost">
            Empty
            <span :if={slot.condition} class="ml-1 text-warning">
              ({condition_label(slot.condition)})
            </span>
          </span>
          <button
            :if={slot.assigned_die != nil and @phase == :allocate_dice}
            phx-click="unassign_die"
            phx-value-card-id={@card.id}
            phx-value-slot-id={slot.id}
            class="btn btn-xs btn-ghost text-error"
          >
            x
          </button>
        </div>
      </div>
    </div>
    """
  end

  defp card_info(assigns) do
    ~H"""
    <%= case @card.type do %>
      <% :battery -> %>
        <span>{@card.properties.dice_count}d{@card.properties.die_sides}</span>
        <span class="ml-1">({@card.properties.remaining_activations}/{@card.properties.max_activations} charges)</span>
      <% :capacitor -> %>
        <span>Stores {length(@card.dice_slots)} dice</span>
      <% :weapon -> %>
        <span>{String.capitalize(to_string(@card.properties.damage_type))}</span>
        <span :if={@card.properties.damage_base > 0} class="ml-1">+{@card.properties.damage_base} base</span>
      <% :armor -> %>
        <span>{String.capitalize(to_string(@card.properties.armor_type))}</span>
        <span :if={@card.properties.shield_base > 0} class="ml-1">+{@card.properties.shield_base} base</span>
      <% :locomotion -> %>
        <span>Speed +{@card.properties.speed_base}</span>
      <% :chassis -> %>
        <span>{@card.properties.hp_max} HP</span>
    <% end %>
    """
  end

  # --- Helpers ---

  defp phase_label(:draw), do: "Draw"
  defp phase_label(:activate_batteries), do: "Activate Batteries"
  defp phase_label(:allocate_dice), do: "Allocate Dice"
  defp phase_label(:resolve), do: "Resolving..."
  defp phase_label(:enemy_turn), do: "Enemy Turn"
  defp phase_label(:ended), do: "Combat Over"

  defp card_border_color(:battery), do: "border-warning"
  defp card_border_color(:capacitor), do: "border-info"
  defp card_border_color(:weapon), do: "border-error"
  defp card_border_color(:armor), do: "border-primary"
  defp card_border_color(:locomotion), do: "border-success"
  defp card_border_color(:chassis), do: "border-base-300"

  defp card_badge(:battery), do: "badge-warning"
  defp card_badge(:capacitor), do: "badge-info"
  defp card_badge(:weapon), do: "badge-error"
  defp card_badge(:armor), do: "badge-primary"
  defp card_badge(:locomotion), do: "badge-success"
  defp card_badge(:chassis), do: "badge-ghost"

  defp card_type_label(:battery), do: "BAT"
  defp card_type_label(:capacitor), do: "CAP"
  defp card_type_label(:weapon), do: "WPN"
  defp card_type_label(:armor), do: "ARM"
  defp card_type_label(:locomotion), do: "MOV"
  defp card_type_label(:chassis), do: "CHS"

  defp condition_label({:min, n}), do: "min #{n}"
  defp condition_label({:max, n}), do: "max #{n}"
  defp condition_label({:exact, n}), do: "= #{n}"
  defp condition_label(:even), do: "even"
  defp condition_label(:odd), do: "odd"
  defp condition_label(nil), do: ""

  defp hp_color(current, total) when current > total * 0.5, do: "progress-success"
  defp hp_color(current, total) when current > total * 0.25, do: "progress-warning"
  defp hp_color(_current, _total), do: "progress-error"
end
