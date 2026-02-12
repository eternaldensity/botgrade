defmodule BotgradeWeb.CombatLive do
  use BotgradeWeb, :live_view

  alias Botgrade.Combat.{CombatServer, CombatSupervisor}
  import BotgradeWeb.CombatComponents
  import BotgradeWeb.CombatCardComponents, only: [card_info_panel: 1]

  @impl true
  def mount(%{"id" => combat_id}, _session, socket) do
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
       campaign_id: nil,
       state: state,
       selected_die: nil,
       error_message: nil,
       info_card: nil
     )}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    campaign_id = params["campaign_id"] || socket.assigns.campaign_id

    combat_number =
      case params["combat_number"] do
        nil -> socket.assigns[:combat_number] || 1
        n -> String.to_integer(n)
      end

    {:noreply, assign(socket, campaign_id: campaign_id, combat_number: combat_number)}
  end

  @impl true
  def handle_info({:state_updated, state}, socket) do
    {:noreply, assign(socket, state: state, error_message: nil, info_card: nil)}
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
  def handle_event("activate_capacitor", %{"card-id" => card_id}, socket) do
    case CombatServer.activate_capacitor(socket.assigns.combat_id, card_id) do
      {:ok, _state} -> {:noreply, assign(socket, error_message: nil)}
      {:error, reason} -> {:noreply, assign(socket, error_message: reason)}
    end
  end

  @impl true
  def handle_event("activate_cpu", %{"card-id" => card_id}, socket) do
    case CombatServer.activate_cpu(socket.assigns.combat_id, card_id) do
      {:ok, _state} -> {:noreply, assign(socket, error_message: nil)}
      {:error, reason} -> {:noreply, assign(socket, error_message: reason)}
    end
  end

  @impl true
  def handle_event("toggle_cpu_discard", %{"card-id" => card_id}, socket) do
    case CombatServer.toggle_cpu_discard(socket.assigns.combat_id, card_id) do
      {:ok, _state} -> {:noreply, assign(socket, error_message: nil)}
      {:error, reason} -> {:noreply, assign(socket, error_message: reason)}
    end
  end

  @impl true
  def handle_event("select_cpu_target_card", %{"card-id" => card_id}, socket) do
    case CombatServer.select_cpu_target_card(socket.assigns.combat_id, card_id) do
      {:ok, _state} -> {:noreply, assign(socket, error_message: nil)}
      {:error, reason} -> {:noreply, assign(socket, error_message: reason)}
    end
  end

  @impl true
  def handle_event("confirm_cpu_ability", _params, socket) do
    case CombatServer.confirm_cpu_ability(socket.assigns.combat_id) do
      {:ok, _state} -> {:noreply, assign(socket, error_message: nil)}
      {:error, reason} -> {:noreply, assign(socket, error_message: reason)}
    end
  end

  @impl true
  def handle_event("cancel_cpu_ability", _params, socket) do
    case CombatServer.cancel_cpu_ability(socket.assigns.combat_id) do
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
  def handle_event("end_turn", _params, socket) do
    case CombatServer.end_turn(socket.assigns.combat_id) do
      {:ok, _state} -> {:noreply, assign(socket, selected_die: nil, error_message: nil)}
      {:error, reason} -> {:noreply, assign(socket, error_message: reason)}
    end
  end

  @impl true
  def handle_event("toggle_scavenge_card", %{"card-id" => card_id}, socket) do
    case CombatServer.toggle_scavenge_card(socket.assigns.combat_id, card_id) do
      {:ok, _state} -> {:noreply, assign(socket, error_message: nil)}
      {:error, reason} -> {:noreply, assign(socket, error_message: reason)}
    end
  end

  @impl true
  def handle_event("confirm_scavenge", _params, socket) do
    case CombatServer.confirm_scavenge(socket.assigns.combat_id) do
      {:ok, _state} -> {:noreply, assign(socket, error_message: nil)}
      {:error, reason} -> {:noreply, assign(socket, error_message: reason)}
    end
  end

  @impl true
  def handle_event("campaign_over", _params, socket) do
    campaign_id = socket.assigns.campaign_id
    Botgrade.Campaign.CampaignPersistence.delete_save(campaign_id)
    {:noreply, push_navigate(socket, to: ~p"/")}
  end

  @impl true
  def handle_event("return_to_map", _params, socket) do
    campaign_id = socket.assigns.campaign_id
    player = socket.assigns.state.player
    player_cards = player.installed ++ player.deck ++ player.hand ++ player.discard
    result = socket.assigns.state.result

    Botgrade.Campaign.CampaignServer.complete_combat(
      campaign_id,
      player_cards,
      player.resources,
      result
    )

    {:noreply, push_navigate(socket, to: ~p"/campaign/#{campaign_id}")}
  end

  @impl true
  def handle_event("next_combat", _params, socket) do
    player = socket.assigns.state.player
    player_cards = player.installed ++ player.deck ++ player.hand ++ player.discard
    combat_id = Base.encode16(:crypto.strong_rand_bytes(4), case: :lower)
    next_number = socket.assigns.combat_number + 1

    {enemy_type, _name, _desc} = Enum.random(Botgrade.Game.StarterDecks.enemy_types())
    enemy_cards = Botgrade.Game.StarterDecks.enemy_deck(enemy_type)
    bonus_cards = Botgrade.Game.StarterDecks.bonus_enemy_cards(next_number, enemy_type)

    {:ok, _pid} = CombatSupervisor.start_combat(combat_id,
      player_cards: player_cards,
      player_resources: player.resources,
      enemy_cards: enemy_cards ++ bonus_cards
    )
    {:noreply, push_navigate(socket, to: ~p"/combat/#{combat_id}?combat_number=#{next_number}")}
  end

  @impl true
  def handle_event("new_combat", _params, socket) do
    {:noreply, push_navigate(socket, to: ~p"/")}
  end

  # --- Card Info ---

  @impl true
  def handle_event("show_card_info", %{"card-id" => card_id}, socket) do
    state = socket.assigns.state
    all_cards =
      state.player.installed ++
      state.player.hand ++
      state.player.deck ++
      state.player.discard
    card = Enum.find(all_cards, &(&1.id == card_id))
    {:noreply, assign(socket, info_card: card)}
  end

  @impl true
  def handle_event("close_card_info", _params, socket) do
    {:noreply, assign(socket, info_card: nil)}
  end

  # --- Render ---

  defp selected_die_value(selected_die, available_dice) do
    if selected_die, do: Enum.at(available_dice, selected_die), else: nil
  end

  @impl true
  def render(assigns) do
    die_value = selected_die_value(assigns.selected_die, assigns.state.player.available_dice)
    assigns = assign(assigns, :die_value, die_value)

    cpu_ability_type =
      if assigns.state.cpu_targeting do
        cpu_card = Enum.find(assigns.state.player.installed, &(&1.id == assigns.state.cpu_targeting))
        if cpu_card, do: cpu_card.properties.cpu_ability.type
      end

    assigns = assign(assigns, :cpu_ability_type, cpu_ability_type)

    ~H"""
    <div class="min-h-screen bg-base-200 flex flex-col">
      <%!-- Quick combat nav when status bar is hidden --%>
      <div :if={is_nil(@campaign_id) and @state.phase in [:ended, :scavenging]} class="px-4 py-2 flex items-center gap-2 bg-base-100 border-b border-base-300">
        <.link navigate={~p"/"} class="btn btn-ghost btn-xs gap-1 text-base-content/60 hover:text-base-content">
          <.icon name="hero-arrow-left-mini" class="size-3.5" />
          Menu
        </.link>
        <span class="badge badge-sm badge-neutral">Fight {@combat_number}</span>
      </div>

      <%!-- Enemy Status (sticky top) --%>
      <.robot_status_bar
        :if={@state.phase not in [:ended, :scavenging]}
        robot={@state.enemy}
        label="ENEMY"
        position={:top}
        combat_number={unless @campaign_id, do: @combat_number}
      />

      <%!-- Enemy Board --%>
      <.enemy_board
        :if={@state.result == :ongoing}
        robot={@state.enemy}
        last_attack_result={@state.last_attack_result}
      />

      <%!-- Main Content --%>
      <div class="flex-1 max-w-5xl w-full mx-auto p-4 space-y-3">
        <%!-- Combat Log --%>
        <.combat_log log={@state.log} />

        <%!-- Error Message --%>
        <div :if={@error_message} class="alert alert-error text-sm">
          {@error_message}
        </div>

        <%!-- Scavenging Phase --%>
        <.scavenge_panel :if={@state.phase == :scavenging} state={@state} />

        <%!-- Victory/Defeat End Screen --%>
        <.end_screen :if={@state.phase == :ended} result={@state.result} campaign_id={@campaign_id} />

        <%!-- Phase Controls --%>
        <.phase_controls
          phase={@state.phase}
          turn_number={@state.turn_number}
          result={@state.result}
          target_lock_active={@state.target_lock_active}
          overclock_active={@state.overclock_active}
          overcharge_bonus={@state.overcharge_bonus}
        />

        <%!-- Dice Pool --%>
        <.dice_pool
          available_dice={@state.player.available_dice}
          selected_die={@selected_die}
          phase={@state.phase}
        />

        <%!-- Player Installed Components --%>
        <.installed_components
          :if={@state.result == :ongoing}
          cards={@state.player.installed}
          last_attack_result={@state.last_attack_result}
          phase={@state.phase}
          cpu_targeting={@state.cpu_targeting}
          cpu_discard_selected={@state.cpu_discard_selected}
          cpu_targeting_mode={@state.cpu_targeting_mode}
        />

        <%!-- Player Hand --%>
        <.card_area
          title="Your Hand"
          cards={@state.player.hand}
          phase={@state.phase}
          selected_die={@selected_die}
          selected_die_value={@die_value}
          count={length(@state.player.hand)}
          cpu_targeting={@state.cpu_targeting}
          cpu_discard_selected={@state.cpu_discard_selected}
          cpu_targeting_mode={@state.cpu_targeting_mode}
          cpu_selected_installed={@state.cpu_selected_installed}
          cpu_ability_type={@cpu_ability_type}
          scrollable
        />
      </div>

      <%!-- Player Status (sticky bottom) --%>
      <.robot_status_bar :if={@state.phase not in [:ended, :scavenging]} robot={@state.player} label="YOU" position={:bottom} />

      <%!-- Card Info Panel (bottom drawer) --%>
      <.card_info_panel card={@info_card} />
    </div>
    """
  end
end
