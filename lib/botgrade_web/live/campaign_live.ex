defmodule BotgradeWeb.CampaignLive do
  use BotgradeWeb, :live_view

  alias Botgrade.Campaign.{CampaignServer, CampaignSupervisor}
  import BotgradeWeb.CampaignComponents

  @impl true
  def mount(%{"id" => campaign_id}, _session, socket) do
    case Registry.lookup(Botgrade.Campaign.Registry, campaign_id) do
      [] ->
        CampaignSupervisor.start_campaign(campaign_id, load_save: true)

      _ ->
        :ok
    end

    if connected?(socket) do
      Phoenix.PubSub.subscribe(Botgrade.PubSub, "campaign:#{campaign_id}")
    end

    state = CampaignServer.get_state(campaign_id)
    current_space = Map.get(state.spaces, state.current_space_id)
    current_zone = current_space && Map.get(state.zones, current_space.zone_id)

    {:ok,
     assign(socket,
       campaign_id: campaign_id,
       state: state,
       current_space: current_space,
       current_zone: current_zone,
       view_mode: :tile,
       shop_inventory: nil,
       event_data: nil,
       error_message: nil
     )}
  end

  @impl true
  def handle_info({:campaign_updated, state}, socket) do
    current_space = Map.get(state.spaces, state.current_space_id)
    current_zone = current_space && Map.get(state.zones, current_space.zone_id)

    {:noreply,
     assign(socket,
       state: state,
       current_space: current_space,
       current_zone: current_zone,
       error_message: nil
     )}
  end

  # --- Player Actions ---

  @impl true
  def handle_event("move_to_space", %{"space-id" => space_id}, socket) do
    case CampaignServer.move_to_space(socket.assigns.campaign_id, space_id) do
      {:combat, combat_id, _state} ->
        {:noreply,
         push_navigate(socket, to: ~p"/combat/#{combat_id}?campaign_id=#{socket.assigns.campaign_id}")}

      {:ok, space, _state} ->
        case space.type do
          :shop ->
            inventory = CampaignServer.shop_cards_for_node(socket.assigns.state)
            {:noreply, assign(socket, view_mode: :shop, shop_inventory: inventory)}

          :rest ->
            {:noreply, assign(socket, view_mode: :rest)}

          :event when not space.cleared ->
            {text, reward_label} = random_event(space)
            {:noreply, assign(socket, view_mode: :event, event_data: %{text: text, reward: reward_label, space: space})}

          :scavenge when not space.cleared ->
            {reward_label, resources} = scavenge_loot(space)
            CampaignServer.scavenge(socket.assigns.campaign_id, resources)
            {:noreply, assign(socket, error_message: "Scavenged: #{reward_label}")}

          :junker when not space.cleared ->
            {:noreply, assign(socket, view_mode: :junker)}

          _ ->
            {:noreply, socket}
        end

      {:error, reason} ->
        {:noreply, assign(socket, error_message: reason)}
    end
  end

  @impl true
  def handle_event("end_turn", _params, socket) do
    case CampaignServer.end_turn(socket.assigns.campaign_id) do
      {:ok, _state} ->
        {:noreply, assign(socket, view_mode: :tile)}

      {:error, reason} ->
        {:noreply, assign(socket, error_message: reason)}
    end
  end

  @impl true
  def handle_event("toggle_view", _params, socket) do
    new_mode = if socket.assigns.view_mode == :zone_overview, do: :tile, else: :zone_overview
    {:noreply, assign(socket, view_mode: new_mode)}
  end

  @impl true
  def handle_event("view_zone", %{"zone-id" => _zone_id}, socket) do
    # Switch back to tile view (zone overview click returns to tile view centered on player)
    {:noreply, assign(socket, view_mode: :tile)}
  end

  @impl true
  def handle_event("enter_junker", _params, socket) do
    {:noreply, assign(socket, view_mode: :junker)}
  end

  @impl true
  def handle_event("enter_shop", _params, socket) do
    inventory = CampaignServer.shop_cards_for_node(socket.assigns.state)
    {:noreply, assign(socket, view_mode: :shop, shop_inventory: inventory)}
  end

  @impl true
  def handle_event("shop_buy", %{"card-index" => idx_str}, socket) do
    idx = String.to_integer(idx_str)

    case CampaignServer.shop_buy(socket.assigns.campaign_id, idx) do
      {:ok, state} ->
        inventory = CampaignServer.shop_cards_for_node(state)
        {:noreply, assign(socket, shop_inventory: inventory)}

      {:error, reason} ->
        {:noreply, assign(socket, error_message: reason)}
    end
  end

  @impl true
  def handle_event("rest_repair", %{"card-id" => card_id}, socket) do
    case CampaignServer.rest_repair(socket.assigns.campaign_id, card_id) do
      {:ok, _state} ->
        {:noreply, assign(socket, error_message: nil)}

      {:error, reason} ->
        {:noreply, assign(socket, error_message: reason)}
    end
  end

  @impl true
  def handle_event("junker_destroy", %{"card-id" => card_id}, socket) do
    case CampaignServer.junker_destroy_card(socket.assigns.campaign_id, card_id) do
      {:ok, scrap, _state} ->
        label = Botgrade.Game.ScrapLogic.format_resources(scrap)
        {:noreply, assign(socket, view_mode: :tile, error_message: "Junked card! Gained: #{label}")}

      {:error, reason} ->
        {:noreply, assign(socket, error_message: reason)}
    end
  end

  @impl true
  def handle_event("leave_space", %{"clear" => "false"}, socket) do
    {:noreply, assign(socket, view_mode: :tile, shop_inventory: nil, event_data: nil)}
  end

  @impl true
  def handle_event("leave_space", _params, socket) do
    CampaignServer.clear_current_space(socket.assigns.campaign_id)
    {:noreply, assign(socket, view_mode: :tile, shop_inventory: nil, event_data: nil)}
  end

  @impl true
  def handle_event("claim_event", _params, socket) do
    if socket.assigns.event_data do
      space = socket.assigns.event_data.space
      resources = event_resources(space)

      if map_size(resources) > 0 do
        state = socket.assigns.state
        merged = merge_resources(state.player_resources, resources)

        CampaignServer.complete_combat(
          socket.assigns.campaign_id,
          state.player_cards,
          merged,
          :player_wins
        )
      else
        CampaignServer.clear_current_space(socket.assigns.campaign_id)
      end
    end

    {:noreply, assign(socket, view_mode: :tile, event_data: nil)}
  end

  @impl true
  def handle_event("save_campaign", _params, socket) do
    CampaignServer.save(socket.assigns.campaign_id)
    {:noreply, assign(socket, error_message: nil)}
  end

  @impl true
  def handle_event("go_home", _params, socket) do
    {:noreply, push_navigate(socket, to: ~p"/")}
  end

  # --- Render ---

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-screen bg-base-200 flex flex-col">
      <%!-- Header --%>
      <div class="sticky top-0 bg-base-100 border-b border-base-300 px-4 py-2 flex items-center justify-between z-10">
        <div class="flex items-center gap-2">
          <button phx-click="go_home" class="btn btn-ghost btn-sm">
            <.icon name="hero-arrow-left" class="size-4" />
          </button>
          <h1 class="font-bold text-lg">Campaign Map</h1>
          <button phx-click="toggle_view" class="btn btn-ghost btn-sm">
            <%= if @view_mode == :zone_overview do %>
              <.icon name="hero-map-pin" class="size-4" /> Tile
            <% else %>
              <.icon name="hero-map" class="size-4" /> Zones
            <% end %>
          </button>
        </div>
        <button phx-click="save_campaign" class="btn btn-ghost btn-sm">
          <.icon name="hero-bookmark" class="size-4" />
          Save
        </button>
      </div>

      <%!-- Error Message --%>
      <div :if={@error_message} class="alert alert-error text-sm mx-4 mt-2">
        {@error_message}
      </div>

      <%!-- Main Content --%>
      <div class="flex-1 max-w-6xl w-full mx-auto p-4 space-y-3">
        <%= case @view_mode do %>
          <% :tile -> %>
            <%!-- Movement Status --%>
            <.movement_status
              movement_points={@state.movement_points}
              max_movement_points={@state.max_movement_points}
              turn_number={@state.turn_number}
            />

            <%!-- Tile Map --%>
            <.tile_detail_map
              spaces={@state.spaces}
              tiles={@state.tiles}
              zones={@state.zones}
              current_space_id={@state.current_space_id}
              visited_spaces={@state.visited_spaces}
              movement_points={@state.movement_points}
            />

            <%!-- Current space detail --%>
            <.space_detail
              :if={@current_space}
              space={@current_space}
              zone={@current_zone}
            />

            <%!-- Player status --%>
            <.campaign_player_status
              player_cards={@state.player_cards}
              player_resources={@state.player_resources}
            />

          <% :zone_overview -> %>
            <.zone_overview_map
              zones={@state.zones}
              current_zone_id={@current_space && @current_space.zone_id}
              visited_spaces={@state.visited_spaces}
              spaces={@state.spaces}
            />

            <.campaign_player_status
              player_cards={@state.player_cards}
              player_resources={@state.player_resources}
            />

          <% :shop -> %>
            <.shop_panel
              inventory={@shop_inventory || []}
              player_resources={@state.player_resources}
            />
            <.campaign_player_status
              player_cards={@state.player_cards}
              player_resources={@state.player_resources}
            />

          <% :rest -> %>
            <.rest_panel
              player_cards={@state.player_cards}
              player_resources={@state.player_resources}
            />

          <% :junker -> %>
            <.junker_panel
              player_cards={@state.player_cards}
            />
            <.campaign_player_status
              player_cards={@state.player_cards}
              player_resources={@state.player_resources}
            />

          <% :event -> %>
            <div :if={@event_data} class="card bg-base-100 shadow-lg border-2 border-info/30">
              <div class="card-body text-center">
                <h2 class="card-title text-info justify-center">
                  <span class="text-2xl">&#10067;</span>
                  Discovery
                </h2>
                <p class="text-base-content/80 mt-2">{@event_data.text}</p>
                <div :if={@event_data.reward} class="mt-2">
                  <span class="badge badge-info">{@event_data.reward}</span>
                </div>
                <div class="card-actions justify-center mt-4">
                  <button phx-click="claim_event" class="btn btn-sm btn-info">
                    Continue
                  </button>
                </div>
              </div>
            </div>
        <% end %>
      </div>
    </div>
    """
  end

  # --- Private Helpers ---

  defp merge_resources(existing, new_resources) do
    Enum.reduce(new_resources, existing, fn {k, v}, acc ->
      Map.update(acc, k, v, &(&1 + v))
    end)
  end
end
