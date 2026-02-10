defmodule BotgradeWeb.CampaignComponents do
  @moduledoc """
  Function components for the campaign map UI.
  Tile-based zone map with space-by-space movement.
  """
  use Phoenix.Component
  import BotgradeWeb.CoreComponents, only: [icon: 1]

  # --- Tile Detail Map (primary gameplay view) ---

  attr :spaces, :map, required: true
  attr :tiles, :map, required: true
  attr :zones, :map, required: true
  attr :current_space_id, :string, required: true
  attr :visited_spaces, :list, required: true
  attr :movement_points, :integer, required: true

  def tile_detail_map(assigns) do
    current_space = Map.get(assigns.spaces, assigns.current_space_id)
    current_zone_id = current_space && current_space.zone_id
    current_tile = Enum.find(Map.values(assigns.tiles), &(&1.zone_id == current_zone_id))

    reachable_ids =
      if current_space && assigns.movement_points > 0 do
        MapSet.new(current_space.connections)
      else
        MapSet.new()
      end

    visited_set = MapSet.new(assigns.visited_spaces)

    # Collect spaces to render: current tile + faded adjacent tile spaces
    {current_spaces, adjacent_spaces} =
      if current_tile do
        cur = Map.values(current_tile.spaces)

        # Find adjacent tiles: follow cross-tile connections from local edge connectors
        adj_zone_ids =
          current_tile.edge_connectors
          |> Map.values()
          |> Enum.reject(&is_nil/1)
          |> Enum.flat_map(fn ec_id ->
            ec = Map.get(assigns.spaces, ec_id)
            if ec, do: ec.connections, else: []
          end)
          |> Enum.map(fn conn_id ->
            space = Map.get(assigns.spaces, conn_id)
            space && space.zone_id
          end)
          |> Enum.reject(&is_nil/1)
          |> Enum.reject(&(&1 == current_zone_id))
          |> Enum.uniq()

        adj =
          assigns.tiles
          |> Map.values()
          |> Enum.filter(&(&1.zone_id in adj_zone_ids))
          |> Enum.flat_map(&Map.values(&1.spaces))

        {cur, adj}
      else
        {Map.values(assigns.spaces), []}
      end

    # Build edges for SVG lines
    all_render_spaces = current_spaces ++ adjacent_spaces
    all_render_map = Map.new(all_render_spaces, &{&1.id, &1})

    edges =
      all_render_spaces
      |> Enum.flat_map(fn space ->
        Enum.map(space.connections, fn target_id ->
          target = Map.get(all_render_map, target_id)

          if target do
            {from_x, from_y} = space.position
            {to_x, to_y} = target.position
            is_cross_tile = space.zone_id != target.zone_id

            traversed =
              MapSet.member?(visited_set, space.id) and
                MapSet.member?(visited_set, target_id)

            %{
              from_x: from_x,
              from_y: from_y,
              to_x: to_x,
              to_y: to_y,
              traversed: traversed,
              cross_tile: is_cross_tile
            }
          end
        end)
        |> Enum.reject(&is_nil/1)
      end)
      |> Enum.uniq_by(fn e -> {min(e.from_x, e.to_x), min(e.from_y, e.to_y), max(e.from_x, e.to_x), max(e.from_y, e.to_y)} end)

    # Zone name for header
    current_zone = current_zone_id && Map.get(assigns.zones, current_zone_id)

    assigns =
      assigns
      |> assign(:current_spaces, current_spaces)
      |> assign(:adjacent_spaces, adjacent_spaces)
      |> assign(:edges, edges)
      |> assign(:reachable_ids, reachable_ids)
      |> assign(:visited_set, visited_set)
      |> assign(:current_zone, current_zone)
      |> assign(:current_tile, current_tile)

    ~H"""
    <div class="w-full overflow-x-auto">
      <div :if={@current_zone} class="text-center mb-1">
        <span class={["font-bold text-sm", zone_text_color(@current_zone.type)]}>
          {@current_zone.name}
        </span>
        <span class="text-xs text-base-content/50 ml-2">
          Danger: {danger_stars(@current_zone.danger_rating)}
        </span>
      </div>
      <svg viewBox={tile_viewbox(@current_tile)} class="w-full h-auto min-w-[400px]" style="max-height: 60vh">
        <defs>
          <filter id="glow">
            <feGaussianBlur stdDeviation="3" result="coloredBlur"/>
            <feMerge>
              <feMergeNode in="coloredBlur"/>
              <feMergeNode in="SourceGraphic"/>
            </feMerge>
          </filter>
        </defs>

        <%!-- Tile background --%>
        <rect
          :if={@current_tile}
          x={elem(@current_tile.bounds, 0)}
          y={elem(@current_tile.bounds, 1)}
          width={elem(@current_tile.bounds, 2)}
          height={elem(@current_tile.bounds, 3)}
          fill={zone_bg_color(@current_zone && @current_zone.type)}
          opacity="0.06"
          rx="8"
        />

        <%!-- Edges --%>
        <line
          :for={edge <- @edges}
          x1={edge.from_x}
          y1={edge.from_y}
          x2={edge.to_x}
          y2={edge.to_y}
          stroke={cond do
            edge.cross_tile -> "#9ca3af"
            edge.traversed -> "#22c55e"
            true -> "#6b7280"
          end}
          stroke-width={if edge.traversed, do: "2.5", else: "1.5"}
          stroke-dasharray={cond do
            edge.cross_tile -> "3,5"
            edge.traversed -> "none"
            true -> "5,3"
          end}
          opacity={if edge.cross_tile, do: "0.3", else: if(edge.traversed, do: "0.7", else: "0.4")}
        />

        <%!-- Adjacent tile spaces (faded, but clickable if reachable) --%>
        <g :for={space <- @adjacent_spaces}>
          <% {sx, sy} = space.position %>
          <% is_reachable = MapSet.member?(@reachable_ids, space.id) %>

          <%!-- Reachable highlight for cross-tile spaces --%>
          <circle
            :if={is_reachable}
            cx={sx}
            cy={sy}
            r="16"
            fill="none"
            stroke="#facc15"
            stroke-width="2"
            stroke-dasharray="4,3"
            opacity="0.7"
          >
            <animate attributeName="stroke-dashoffset" values="0;14" dur="1.5s" repeatCount="indefinite" />
          </circle>

          <circle
            cx={sx}
            cy={sy}
            r={if is_reachable, do: "12", else: "10"}
            fill={space_fill(space.type, space.cleared)}
            stroke={space_stroke(space.type, false)}
            stroke-width="1"
            opacity={if is_reachable, do: "0.8", else: "0.25"}
            class={if is_reachable, do: "cursor-pointer", else: ""}
            phx-click={if is_reachable, do: "move_to_space"}
            phx-value-space-id={if is_reachable, do: space.id}
          />
          <text
            x={sx}
            y={sy + 3}
            text-anchor="middle"
            font-size="10"
            fill="white"
            pointer-events="none"
            opacity={if is_reachable, do: "0.9", else: "0.25"}
          >
            {space_icon(space.type)}
          </text>
          <text
            :if={is_reachable}
            x={sx}
            y={sy + 22}
            text-anchor="middle"
            font-size="7"
            fill="currentColor"
            opacity="0.6"
            pointer-events="none"
          >
            {space.label}
          </text>
        </g>

        <%!-- Current tile spaces --%>
        <g :for={space <- @current_spaces}>
          <% {sx, sy} = space.position %>
          <% is_current = space.id == @current_space_id %>
          <% is_reachable = MapSet.member?(@reachable_ids, space.id) %>

          <%!-- Current space pulsing ring --%>
          <circle
            :if={is_current}
            cx={sx}
            cy={sy}
            r="20"
            fill="none"
            stroke="#22c55e"
            stroke-width="3"
            opacity="0.6"
            filter="url(#glow)"
          >
            <animate attributeName="r" values="18;22;18" dur="2s" repeatCount="indefinite" />
            <animate attributeName="opacity" values="0.6;0.3;0.6" dur="2s" repeatCount="indefinite" />
          </circle>

          <%!-- Reachable space highlight --%>
          <circle
            :if={is_reachable and not is_current}
            cx={sx}
            cy={sy}
            r="18"
            fill="none"
            stroke="#facc15"
            stroke-width="2"
            stroke-dasharray="4,3"
            opacity="0.6"
          >
            <animate attributeName="stroke-dashoffset" values="0;14" dur="1.5s" repeatCount="indefinite" />
          </circle>

          <%!-- Space circle --%>
          <circle
            cx={sx}
            cy={sy}
            r="14"
            fill={space_fill(space.type, space.cleared)}
            stroke={space_stroke(space.type, is_current)}
            stroke-width={if is_current, do: "3", else: "2"}
            opacity={if space.cleared and not is_current, do: "0.5", else: "1"}
            class={if is_reachable, do: "cursor-pointer", else: ""}
            phx-click={if is_reachable, do: "move_to_space"}
            phx-value-space-id={if is_reachable, do: space.id}
          />

          <%!-- Space icon --%>
          <text
            x={sx}
            y={sy + 4}
            text-anchor="middle"
            font-size="12"
            fill="white"
            pointer-events="none"
            opacity={if space.cleared and not is_current, do: "0.5", else: "1"}
          >
            {space_icon(space.type)}
          </text>

          <%!-- Space label --%>
          <text
            x={sx}
            y={sy + 26}
            text-anchor="middle"
            font-size="8"
            fill="currentColor"
            opacity={if is_reachable, do: "0.8", else: "0.45"}
            pointer-events="none"
          >
            {space.label}
          </text>

          <%!-- Danger dots for enemy spaces --%>
          <g :if={space.type == :enemy and not space.cleared} pointer-events="none">
            <circle
              :for={i <- 1..space.danger_rating}
              cx={sx - (space.danger_rating - 1) * 3 + (i - 1) * 6}
              cy={sy - 20}
              r="2"
              fill={danger_dot_color(space.danger_rating)}
              opacity="0.8"
            />
          </g>

          <%!-- Cleared checkmark --%>
          <text
            :if={space.cleared and space.type not in [:start, :edge_connector, :empty]}
            x={sx + 10}
            y={sy - 8}
            font-size="10"
            fill="#22c55e"
            pointer-events="none"
          >
            &#10003;
          </text>
        </g>
      </svg>
    </div>
    """
  end

  # --- Zone Overview Map ---

  attr :zones, :map, required: true
  attr :current_zone_id, :string, required: true
  attr :visited_spaces, :list, required: true
  attr :spaces, :map, required: true

  def zone_overview_map(assigns) do
    zone_list = Map.values(assigns.zones) |> Enum.sort_by(fn z -> z.grid_pos end)

    # Determine which zones have been visited
    visited_zone_ids =
      assigns.visited_spaces
      |> Enum.map(fn space_id ->
        space = Map.get(assigns.spaces, space_id)
        space && space.zone_id
      end)
      |> Enum.reject(&is_nil/1)
      |> MapSet.new()

    assigns =
      assigns
      |> assign(:zone_list, zone_list)
      |> assign(:visited_zone_ids, visited_zone_ids)

    ~H"""
    <div class="w-full overflow-x-auto">
      <svg viewBox="0 0 1000 600" class="w-full h-auto min-w-[400px]" style="max-height: 60vh">
        <%!-- Zone neighbor connections --%>
        <g :for={zone <- @zone_list}>
          <line
            :for={neighbor_id <- zone.neighbors}
            :if={neighbor_id > zone.id}
            x1={zone_center_x(zone)}
            y1={zone_center_y(zone)}
            x2={zone_center_x(Map.get(@zones, neighbor_id))}
            y2={zone_center_y(Map.get(@zones, neighbor_id))}
            stroke="#6b7280"
            stroke-width="2"
            opacity="0.3"
          />
        </g>

        <%!-- Zone rectangles --%>
        <g :for={zone <- @zone_list}>
          <% is_current = zone.id == @current_zone_id %>
          <% is_visited = MapSet.member?(@visited_zone_ids, zone.id) %>
          <% {zx, zy} = zone_rect_pos(zone) %>

          <rect
            x={zx}
            y={zy}
            width="200"
            height="150"
            rx="12"
            fill={zone_bg_color(zone.type)}
            opacity={cond do
              is_current -> "0.3"
              is_visited -> "0.15"
              true -> "0.08"
            end}
            stroke={if is_current, do: "#22c55e", else: zone_bg_color(zone.type)}
            stroke-width={if is_current, do: "3", else: "1"}
            class="cursor-pointer"
            phx-click="view_zone"
            phx-value-zone-id={zone.id}
          />

          <%!-- Zone name --%>
          <text
            x={zx + 100}
            y={zy + 65}
            text-anchor="middle"
            font-size="13"
            fill="currentColor"
            class="font-bold"
            opacity={if is_visited, do: "0.9", else: "0.5"}
            pointer-events="none"
          >
            {zone.name}
          </text>

          <%!-- Zone type + danger --%>
          <text
            x={zx + 100}
            y={zy + 85}
            text-anchor="middle"
            font-size="10"
            fill="currentColor"
            opacity="0.5"
            pointer-events="none"
          >
            {String.capitalize(to_string(zone.type))} | {danger_stars(zone.danger_rating)}
          </text>

          <%!-- Current indicator --%>
          <text
            :if={is_current}
            x={zx + 100}
            y={zy + 110}
            text-anchor="middle"
            font-size="11"
            fill="#22c55e"
            class="font-bold"
            pointer-events="none"
          >
            YOU ARE HERE
          </text>
        </g>
      </svg>
    </div>
    """
  end

  # --- Movement Status ---

  attr :movement_points, :integer, required: true
  attr :max_movement_points, :integer, required: true
  attr :turn_number, :integer, required: true

  def movement_status(assigns) do
    ~H"""
    <div class="flex items-center justify-between bg-base-100 rounded-lg border border-base-300 px-3 py-2">
      <div class="flex items-center gap-3">
        <span class="text-sm font-semibold text-base-content/70">Turn {@turn_number}</span>
        <div class="flex items-center gap-1.5">
          <span class="text-sm">Move:</span>
          <div class="flex gap-0.5">
            <span
              :for={i <- 1..@max_movement_points}
              class={[
                "w-3 h-3 rounded-full border",
                if(i <= @movement_points,
                  do: "bg-success border-success",
                  else: "bg-base-300 border-base-300")
              ]}
            />
          </div>
          <span class="text-xs text-base-content/50">
            {@movement_points}/{@max_movement_points}
          </span>
        </div>
      </div>
      <button phx-click="end_turn" class="btn btn-xs btn-outline" disabled={@movement_points <= 0}>
        End Turn
      </button>
    </div>
    """
  end

  # --- Space Detail Panel ---

  attr :space, :map, required: true
  attr :zone, :map, default: nil

  def space_detail(assigns) do
    ~H"""
    <div class="card bg-base-100 shadow-sm border border-base-300">
      <div class="card-body p-4">
        <div class="flex items-center gap-2">
          <span class={["text-2xl", space_icon_class(@space.type)]}>{space_icon(@space.type)}</span>
          <div>
            <h3 class="font-bold">{@space.label}</h3>
            <span class={["badge badge-sm", space_type_badge(@space.type)]}>
              {space_type_label(@space.type)}
            </span>
          </div>
        </div>
        <div :if={@zone} class="text-sm text-base-content/60 mt-1">
          <span>Zone: {@zone.name}</span>
          <span class="mx-1">|</span>
          <span>Danger: {danger_stars(@space.danger_rating)}</span>
        </div>
        <div :if={@space.type == :enemy && @space.enemy_type && !@space.cleared} class="text-sm mt-1">
          <span class="text-error font-semibold">Enemy: {enemy_display_name(@space.enemy_type)}</span>
        </div>
        <button :if={@space.type == :shop} phx-click="enter_shop" class="btn btn-sm btn-warning mt-2">
          <span>&#128722;</span> Enter Shop
        </button>
      </div>
    </div>
    """
  end

  # --- Campaign Player Status ---

  attr :player_cards, :list, required: true
  attr :player_resources, :map, required: true

  def campaign_player_status(assigns) do
    card_counts =
      assigns.player_cards
      |> Enum.group_by(& &1.type)
      |> Map.new(fn {type, cards} -> {type, length(cards)} end)

    damaged_count = Enum.count(assigns.player_cards, &(&1.damage == :damaged))

    assigns =
      assigns
      |> assign(:card_counts, card_counts)
      |> assign(:total_cards, length(assigns.player_cards))
      |> assign(:damaged_count, damaged_count)

    ~H"""
    <div class="card bg-base-100 shadow-sm border border-base-300">
      <div class="card-body p-3">
        <h3 class="card-title text-sm">
          <.icon name="hero-cpu-chip" class="size-4 text-primary" />
          Your Bot
          <span class="badge badge-sm badge-ghost">{@total_cards} cards</span>
          <span :if={@damaged_count > 0} class="badge badge-sm badge-warning">{@damaged_count} damaged</span>
        </h3>

        <div class="flex flex-wrap gap-2 text-xs">
          <span :for={{type, count} <- Enum.sort_by(@card_counts, fn {k, _} -> Atom.to_string(k) end)} class="flex items-center gap-1">
            <span class={card_type_color(type)}>{card_type_short(type)}</span>
            <span class="font-mono">{count}</span>
          </span>
        </div>

        <div :if={map_size(@player_resources) > 0} class="flex flex-wrap gap-2 text-xs mt-1 border-t border-base-300 pt-2">
          <span
            :for={{type, count} <- Enum.sort_by(@player_resources, fn {k, _} -> Atom.to_string(k) end)}
            :if={count > 0}
            class="flex items-center gap-0.5 text-warning/80 font-semibold"
          >
            <span class="text-[10px]">{scrap_label(type)}</span>
            <span class="font-mono">{count}</span>
          </span>
          <span :if={Enum.all?(@player_resources, fn {_, v} -> v == 0 end)} class="text-base-content/40">
            No resources
          </span>
        </div>
      </div>
    </div>
    """
  end

  # --- Shop Panel ---

  attr :inventory, :list, required: true
  attr :player_resources, :map, required: true

  def shop_panel(assigns) do
    ~H"""
    <div class="card bg-base-100 shadow-lg border-2 border-warning/30">
      <div class="card-body">
        <div class="flex items-center justify-between">
          <h2 class="card-title text-warning">
            <span class="text-2xl">&#128722;</span>
            Scrap Trader
          </h2>
          <button phx-click="leave_space" phx-value-clear="false" class="btn btn-sm btn-outline btn-success gap-1">
            <.icon name="hero-arrow-left" class="size-4" /> Leave Shop
          </button>
        </div>
        <p class="text-sm text-base-content/60">Trade your scrap for components.</p>

        <div class="grid grid-cols-1 md:grid-cols-2 gap-3 mt-2">
          <div
            :for={{_card_with_price, idx} <- Enum.with_index(@inventory)}
            class="rounded-xl border-2 border-base-300 p-3"
          >
            <% {card, price} = Enum.at(@inventory, idx) %>
            <div class="flex items-center gap-1.5 mb-2">
              <span class={["font-bold", card_type_color(card.type)]}>{card.name}</span>
              <span class="badge badge-xs badge-ghost">{card_type_short(card.type)}</span>
            </div>
            <div class="text-xs text-base-content/60 mb-2">
              {card_summary(card)}
            </div>
            <% can_afford = Enum.all?(price, fn {res, amt} -> Map.get(@player_resources, res, 0) >= amt end) %>
            <div class="flex items-center justify-between">
              <div class="flex gap-1.5 text-xs">
                <span
                  :for={{resource, amount} <- Enum.sort_by(price, fn {k, _} -> Atom.to_string(k) end)}
                  class={[
                    "font-mono",
                    if(Map.get(@player_resources, resource, 0) >= amount, do: "text-success", else: "text-error")
                  ]}
                >
                  {amount} {scrap_label(resource)}
                </span>
              </div>
              <button
                phx-click="shop_buy"
                phx-value-card-index={idx}
                class="btn btn-xs btn-warning"
                disabled={!can_afford}
              >
                Buy
              </button>
            </div>
          </div>
        </div>

      </div>
    </div>
    """
  end

  # --- Rest Panel ---

  attr :player_cards, :list, required: true
  attr :player_resources, :map, required: true

  def rest_panel(assigns) do
    damaged_cards =
      assigns.player_cards
      |> Enum.with_index()
      |> Enum.filter(fn {card, _idx} -> card.damage == :damaged end)

    assigns = assign(assigns, :damaged_cards, damaged_cards)

    ~H"""
    <div class="card bg-base-100 shadow-lg border-2 border-success/30">
      <div class="card-body">
        <h2 class="card-title text-success">
          <span class="text-2xl">&#128295;</span>
          Repair Bay
        </h2>
        <p class="text-sm text-base-content/60">
          Repair damaged components. Each repair costs 2 Metal + 1 Wire.
        </p>

        <div :if={@damaged_cards == []} class="text-center text-base-content/50 py-4">
          All components are in good condition.
        </div>

        <div :if={@damaged_cards != []} class="space-y-2 mt-2">
          <div
            :for={{card, _idx} <- @damaged_cards}
            class="flex items-center justify-between rounded-lg border border-warning/30 p-3"
          >
            <div>
              <span class={["font-bold", card_type_color(card.type)]}>{card.name}</span>
              <span class="badge badge-xs badge-warning ml-1">DAMAGED</span>
              <div class="text-xs text-base-content/50 mt-0.5">
                HP: {card.current_hp}/{Map.get(card.properties, :card_hp, 2)}
              </div>
            </div>
            <button
              phx-click="rest_repair"
              phx-value-card-id={card.id}
              class="btn btn-xs btn-success"
              disabled={Map.get(@player_resources, :metal, 0) < 2 or Map.get(@player_resources, :wire, 0) < 1}
            >
              Repair
            </button>
          </div>
        </div>

        <div class="card-actions justify-center mt-4">
          <button phx-click="leave_space" class="btn btn-sm btn-ghost">
            Leave Repair Bay
          </button>
        </div>
      </div>
    </div>
    """
  end

  # --- Helper Functions ---

  defp tile_viewbox(nil), do: "0 0 1000 600"
  defp tile_viewbox(tile) do
    {x, y, w, h} = tile.bounds
    # Add padding around the tile
    pad = 30
    "#{x - pad} #{y - pad} #{w + pad * 2} #{h + pad * 2}"
  end

  defp zone_rect_pos(zone) do
    {col, row} = zone.grid_pos
    {col * 240 + 20, row * 190 + 15}
  end

  defp zone_center_x(nil), do: 0
  defp zone_center_x(zone) do
    {x, _y} = zone_rect_pos(zone)
    x + 100
  end

  defp zone_center_y(nil), do: 0
  defp zone_center_y(zone) do
    {_x, y} = zone_rect_pos(zone)
    y + 75
  end

  defp zone_bg_color(:industrial), do: "#f59e0b"
  defp zone_bg_color(:residential), do: "#3b82f6"
  defp zone_bg_color(:commercial), do: "#a855f7"
  defp zone_bg_color(_), do: "#6b7280"

  defp zone_text_color(:industrial), do: "text-amber-400"
  defp zone_text_color(:residential), do: "text-blue-400"
  defp zone_text_color(:commercial), do: "text-purple-400"
  defp zone_text_color(_), do: "text-base-content"

  defp space_fill(:start, _), do: "#6b7280"
  defp space_fill(:exit, _), do: "#7c3aed"
  defp space_fill(:enemy, true), do: "#6b7280"
  defp space_fill(:enemy, _), do: "#ef4444"
  defp space_fill(:shop, true), do: "#6b7280"
  defp space_fill(:shop, _), do: "#eab308"
  defp space_fill(:rest, true), do: "#6b7280"
  defp space_fill(:rest, _), do: "#22c55e"
  defp space_fill(:event, true), do: "#6b7280"
  defp space_fill(:event, _), do: "#3b82f6"
  defp space_fill(:scavenge, true), do: "#6b7280"
  defp space_fill(:scavenge, _), do: "#a16207"
  defp space_fill(:edge_connector, _), do: "#4b5563"
  defp space_fill(:empty, _), do: "#374151"
  defp space_fill(_, _), do: "#374151"

  defp space_stroke(:start, _), do: "#9ca3af"
  defp space_stroke(:exit, _), do: "#a78bfa"
  defp space_stroke(_, true), do: "#22c55e"
  defp space_stroke(:enemy, _), do: "#f87171"
  defp space_stroke(:shop, _), do: "#fbbf24"
  defp space_stroke(:rest, _), do: "#4ade80"
  defp space_stroke(:event, _), do: "#60a5fa"
  defp space_stroke(:scavenge, _), do: "#ca8a04"
  defp space_stroke(:edge_connector, _), do: "#6b7280"
  defp space_stroke(:empty, _), do: "#6b7280"
  defp space_stroke(_, _), do: "#6b7280"

  defp space_icon(:start), do: "\u{1F3F3}"
  defp space_icon(:exit), do: "\u{2B50}"
  defp space_icon(:enemy), do: "\u{2694}"
  defp space_icon(:shop), do: "\u{1F6D2}"
  defp space_icon(:rest), do: "\u{1F527}"
  defp space_icon(:event), do: "?"
  defp space_icon(:scavenge), do: "\u{2699}"
  defp space_icon(:edge_connector), do: "\u{2192}"
  defp space_icon(:empty), do: "\u{00B7}"
  defp space_icon(_), do: "\u{00B7}"

  defp space_icon_class(:enemy), do: "text-error"
  defp space_icon_class(:shop), do: "text-warning"
  defp space_icon_class(:rest), do: "text-success"
  defp space_icon_class(:event), do: "text-info"
  defp space_icon_class(:scavenge), do: "text-amber-600"
  defp space_icon_class(_), do: "text-base-content"

  defp space_type_badge(:enemy), do: "badge-error"
  defp space_type_badge(:shop), do: "badge-warning"
  defp space_type_badge(:rest), do: "badge-success"
  defp space_type_badge(:event), do: "badge-info"
  defp space_type_badge(:exit), do: "badge-secondary"
  defp space_type_badge(:scavenge), do: "badge-warning"
  defp space_type_badge(_), do: "badge-ghost"

  defp space_type_label(:start), do: "Start"
  defp space_type_label(:exit), do: "Research Lab"
  defp space_type_label(:enemy), do: "Combat"
  defp space_type_label(:shop), do: "Shop"
  defp space_type_label(:rest), do: "Rest"
  defp space_type_label(:event), do: "Event"
  defp space_type_label(:scavenge), do: "Scavenge"
  defp space_type_label(:edge_connector), do: "Zone Border"
  defp space_type_label(:empty), do: "Passage"
  defp space_type_label(_), do: "Unknown"

  defp danger_stars(rating) do
    String.duplicate("\u{2605}", rating) <> String.duplicate("\u{2606}", 5 - rating)
  end

  defp danger_dot_color(1), do: "#22c55e"
  defp danger_dot_color(2), do: "#eab308"
  defp danger_dot_color(3), do: "#f97316"
  defp danger_dot_color(4), do: "#ef4444"
  defp danger_dot_color(5), do: "#dc2626"
  defp danger_dot_color(_), do: "#6b7280"

  defp enemy_display_name("rogue"), do: "Rogue Bot"
  defp enemy_display_name("ironclad"), do: "Ironclad"
  defp enemy_display_name("strikebolt"), do: "Strikebolt"
  defp enemy_display_name("hexapod"), do: "Hexapod"
  defp enemy_display_name(other), do: String.capitalize(other)

  defp card_type_color(:weapon), do: "text-error"
  defp card_type_color(:armor), do: "text-primary"
  defp card_type_color(:battery), do: "text-warning"
  defp card_type_color(:capacitor), do: "text-info"
  defp card_type_color(:chassis), do: "text-base-content/70"
  defp card_type_color(:cpu), do: "text-secondary"
  defp card_type_color(:locomotion), do: "text-success"
  defp card_type_color(:utility), do: "text-accent"

  defp card_type_short(:weapon), do: "WPN"
  defp card_type_short(:armor), do: "ARM"
  defp card_type_short(:battery), do: "BAT"
  defp card_type_short(:capacitor), do: "CAP"
  defp card_type_short(:chassis), do: "CHS"
  defp card_type_short(:cpu), do: "CPU"
  defp card_type_short(:locomotion), do: "LOC"
  defp card_type_short(:utility), do: "UTL"

  defp card_summary(card) do
    case card.type do
      :weapon ->
        dmg_type = Map.get(card.properties, :damage_type, :kinetic)
        base = Map.get(card.properties, :damage_base, 0)
        multiplier = Map.get(card.properties, :damage_multiplier, 1)
        slot_count = length(card.dice_slots)
        dice_part =
          cond do
            multiplier > 1 and slot_count == 1 -> "die x#{multiplier}"
            multiplier > 1 -> "#{slot_count} dice x#{multiplier}"
            slot_count == 1 -> "die"
            true -> "#{slot_count} dice"
          end
        base_part =
          cond do
            base > 0 -> " + #{base}"
            base < 0 -> " - #{abs(base)}"
            true -> ""
          end
        cond_part = slot_condition_summary(card)
        dual_part = dual_mode_summary(card)
        max_acts = Map.get(card.properties, :max_activations_per_turn)
        acts_part = if max_acts, do: " (#{max_acts}x)", else: ""
        self_dmg = Map.get(card.properties, :self_damage, 0)
        self_part = if self_dmg > 0, do: " [self: #{self_dmg}]", else: ""
        escalating = if Map.get(card.properties, :escalating, false), do: " (+1/wpn)", else: ""
        "#{String.capitalize(to_string(dmg_type))} #{dice_part}#{base_part}#{cond_part}#{dual_part}#{acts_part}#{self_part}#{escalating}"

      :armor ->
        armor_type = Map.get(card.properties, :armor_type, :plating)
        base = Map.get(card.properties, :shield_base, 0)
        slot_count = length(card.dice_slots)
        dice_part = if slot_count == 1, do: "die", else: "#{slot_count} dice"
        base_part = if base > 0, do: " + #{base}", else: ""
        cond_part = slot_condition_summary(card)
        "#{String.capitalize(to_string(armor_type))} #{dice_part}#{base_part}#{cond_part}"

      :battery ->
        count = Map.get(card.properties, :dice_count, 1)
        sides = Map.get(card.properties, :die_sides, 6)
        acts = Map.get(card.properties, :max_activations, 3)
        "#{count}d#{sides}, #{acts} charges"

      :capacitor ->
        stored = Map.get(card.properties, :max_stored, 2)
        "Stores #{stored} dice (persist between turns)"

      :cpu ->
        cpu_ability_summary(Map.get(card.properties, :cpu_ability))

      :chassis ->
        "#{Map.get(card.properties, :card_hp, 0)} HP"

      :locomotion ->
        "Speed +#{Map.get(card.properties, :speed_base, 1)}"

      :utility ->
        utility_ability_summary(Map.get(card.properties, :utility_ability))

      _ ->
        ""
    end
  end

  defp slot_condition_summary(card) do
    conditions =
      card.dice_slots
      |> Enum.filter(& &1.condition)
      |> Enum.map(&condition_text(&1.condition))
      |> Enum.uniq()

    case conditions do
      [] -> ""
      [c] -> " (#{c})"
      cs -> " (#{Enum.join(cs, ", ")})"
    end
  end

  defp dual_mode_summary(card) do
    case Map.get(card.properties, :dual_mode) do
      nil -> ""
      %{condition: cond, armor_type: type, shield_base: base} ->
        type_name = String.capitalize(to_string(type))
        cond_text = condition_text(cond)
        base_text = if base > 0, do: " +#{base}", else: ""
        " | If #{cond_text}: #{type_name}#{base_text}"
    end
  end

  defp condition_text({:min, n}), do: "#{n}+"
  defp condition_text({:max, n}), do: "#{n}-"
  defp condition_text({:exact, n}), do: "=#{n}"
  defp condition_text(:even), do: "even"
  defp condition_text(:odd), do: "odd"
  defp condition_text(nil), do: ""

  defp cpu_ability_summary(%{type: :discard_draw, discard_count: d, draw_count: r}),
    do: "Discard #{d}, Draw #{r}"
  defp cpu_ability_summary(%{type: :reflex_block}), do: "Boost armor shield by +1"
  defp cpu_ability_summary(%{type: :target_lock}), do: "Next weapon bypasses defenses"
  defp cpu_ability_summary(%{type: :overclock_battery}), do: "Next battery activates twice"
  defp cpu_ability_summary(%{type: :siphon_power}), do: "Spend 2 shield to restore a charge"
  defp cpu_ability_summary(%{type: :extra_activation}), do: "Reactivate a used card"
  defp cpu_ability_summary(_), do: "Processing Unit"

  defp utility_ability_summary(:beam_split), do: "Split a die into two halves (2x/turn)"
  defp utility_ability_summary(:overcharge), do: "Spend 3+ die for +1 weapon damage"
  defp utility_ability_summary(_), do: "Utility"

  defp scrap_label(:metal), do: "Metal"
  defp scrap_label(:wire), do: "Wire"
  defp scrap_label(:plastic), do: "Plastic"
  defp scrap_label(:grease), do: "Grease"
  defp scrap_label(:chips), do: "Chips"

  @scavenge_loot [
    {"+1 Metal", %{metal: 1}},
    {"+1 Wire", %{wire: 1}},
    {"+1 Plastic", %{plastic: 1}},
    {"+1 Grease", %{grease: 1}},
    {"+1 Metal, +1 Wire", %{metal: 1, wire: 1}},
    {"+1 Metal, +1 Plastic", %{metal: 1, plastic: 1}}
  ]

  def scavenge_loot(space) do
    idx = :erlang.phash2(space.id, length(@scavenge_loot))
    Enum.at(@scavenge_loot, idx)
  end

  @events [
    {"You find a stash of scrap metal hidden in a collapsed storefront.", "+2 Metal", %{metal: 2}},
    {"A broken bot left behind some wiring. Still usable.", "+2 Wire", %{wire: 2}},
    {"You salvage plastic casing from an abandoned kiosk.", "+2 Plastic", %{plastic: 2}},
    {"An oil drum leaks precious lubricant. You collect what you can.", "+2 Grease", %{grease: 2}},
    {"A shattered circuit board yields a few intact chips.", "+1 Chips", %{chips: 1}},
    {"Nothing of note here. The city is quiet, for now.", nil, %{}}
  ]

  def random_event(space) do
    idx = :erlang.phash2(space.id, length(@events))
    {text, reward_label, _resources} = Enum.at(@events, idx)
    {text, reward_label}
  end

  def event_resources(space) do
    idx = :erlang.phash2(space.id, length(@events))
    {_text, _reward_label, resources} = Enum.at(@events, idx)
    resources
  end
end
