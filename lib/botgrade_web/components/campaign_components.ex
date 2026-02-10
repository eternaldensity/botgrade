defmodule BotgradeWeb.CampaignComponents do
  @moduledoc """
  Function components for the campaign map UI.
  """
  use Phoenix.Component
  import BotgradeWeb.CoreComponents, only: [icon: 1]

  # --- Campaign Map (SVG) ---

  attr :nodes, :map, required: true
  attr :current_node_id, :string, required: true
  attr :visited_nodes, :list, required: true

  def campaign_map(assigns) do
    nodes_list = Map.values(assigns.nodes)
    current_node = Map.get(assigns.nodes, assigns.current_node_id)
    adjacent_ids = if current_node, do: MapSet.new(current_node.edges), else: MapSet.new()
    visited_set = MapSet.new(assigns.visited_nodes)

    # Build edge list for SVG lines
    edges =
      nodes_list
      |> Enum.flat_map(fn node ->
        Enum.map(node.edges, fn target_id ->
          target = Map.get(assigns.nodes, target_id)

          if target do
            {from_x, from_y} = node.position
            {to_x, to_y} = target.position

            traversed =
              MapSet.member?(visited_set, node.id) and
                MapSet.member?(visited_set, target_id)

            %{
              from_x: from_x,
              from_y: from_y,
              to_x: to_x,
              to_y: to_y,
              traversed: traversed
            }
          end
        end)
        |> Enum.reject(&is_nil/1)
      end)

    # Build zone background rects
    zone_rects = build_zone_rects(nodes_list)

    assigns =
      assigns
      |> assign(:nodes_list, nodes_list)
      |> assign(:edges, edges)
      |> assign(:zone_rects, zone_rects)
      |> assign(:adjacent_ids, adjacent_ids)
      |> assign(:visited_set, visited_set)
      |> assign(:current_node, current_node)

    ~H"""
    <div class="w-full overflow-x-auto">
      <svg viewBox="0 0 1000 600" class="w-full h-auto min-w-[600px]" style="max-height: 70vh">
        <defs>
          <filter id="glow">
            <feGaussianBlur stdDeviation="3" result="coloredBlur"/>
            <feMerge>
              <feMergeNode in="coloredBlur"/>
              <feMergeNode in="SourceGraphic"/>
            </feMerge>
          </filter>
        </defs>

        <%!-- Zone background rects --%>
        <rect
          :for={zr <- @zone_rects}
          x={zr.x}
          y="0"
          width={zr.width}
          height="600"
          fill={zone_bg_color(zr.type)}
          opacity="0.08"
        />
        <text
          :for={zr <- @zone_rects}
          x={zr.x + zr.width / 2}
          y="20"
          text-anchor="middle"
          font-size="11"
          fill="currentColor"
          opacity="0.35"
          class="font-semibold"
        >
          {zr.name}
        </text>

        <%!-- Edges --%>
        <line
          :for={edge <- @edges}
          x1={edge.from_x}
          y1={edge.from_y}
          x2={edge.to_x}
          y2={edge.to_y}
          stroke={if edge.traversed, do: "#22c55e", else: "#6b7280"}
          stroke-width={if edge.traversed, do: "3", else: "1.5"}
          stroke-dasharray={if edge.traversed, do: "none", else: "6,4"}
          opacity={if edge.traversed, do: "0.7", else: "0.4"}
        />

        <%!-- Nodes --%>
        <g :for={node <- @nodes_list}>
          <% {nx, ny} = node.position %>
          <% is_current = node.id == @current_node_id %>
          <% is_adjacent = MapSet.member?(@adjacent_ids, node.id) %>
          <% _is_visited = MapSet.member?(@visited_set, node.id) %>

          <%!-- Current node pulsing ring --%>
          <circle
            :if={is_current}
            cx={nx}
            cy={ny}
            r="28"
            fill="none"
            stroke="#22c55e"
            stroke-width="3"
            opacity="0.6"
            filter="url(#glow)"
          >
            <animate attributeName="r" values="26;30;26" dur="2s" repeatCount="indefinite" />
            <animate attributeName="opacity" values="0.6;0.3;0.6" dur="2s" repeatCount="indefinite" />
          </circle>

          <%!-- Adjacent node highlight ring --%>
          <circle
            :if={is_adjacent and not is_current}
            cx={nx}
            cy={ny}
            r="25"
            fill="none"
            stroke="#facc15"
            stroke-width="2"
            stroke-dasharray="4,3"
            opacity="0.6"
          >
            <animate attributeName="stroke-dashoffset" values="0;14" dur="1.5s" repeatCount="indefinite" />
          </circle>

          <%!-- Clickable node circle --%>
          <circle
            cx={nx}
            cy={ny}
            r="20"
            fill={node_fill(node.type, node.cleared)}
            stroke={node_stroke(node.type, is_current)}
            stroke-width={if is_current, do: "3", else: "2"}
            opacity={if node.cleared and not is_current, do: "0.5", else: "1"}
            class={if is_adjacent, do: "cursor-pointer", else: ""}
            phx-click={if is_adjacent, do: "move_to_node"}
            phx-value-node-id={if is_adjacent, do: node.id}
          />

          <%!-- Node icon --%>
          <text
            x={nx}
            y={ny + 5}
            text-anchor="middle"
            font-size="16"
            fill="white"
            pointer-events="none"
            opacity={if node.cleared and not is_current, do: "0.5", else: "1"}
          >
            {node_icon(node.type)}
          </text>

          <%!-- Node label --%>
          <text
            x={nx}
            y={ny + 38}
            text-anchor="middle"
            font-size="9"
            fill="currentColor"
            opacity={if is_adjacent, do: "0.8", else: "0.45"}
            pointer-events="none"
          >
            {node.label}
          </text>

          <%!-- Danger rating dots --%>
          <g :if={node.type in [:combat, :exit]} pointer-events="none">
            <circle
              :for={i <- 1..node.danger_rating}
              cx={nx - (node.danger_rating - 1) * 4 + (i - 1) * 8}
              cy={ny - 28}
              r="3"
              fill={danger_dot_color(node.danger_rating)}
              opacity="0.8"
            />
          </g>

          <%!-- Cleared checkmark --%>
          <text
            :if={node.cleared and node.type not in [:start]}
            x={nx + 14}
            y={ny - 12}
            font-size="12"
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

  # --- Node Detail Panel ---

  attr :node, :map, required: true

  def node_detail(assigns) do
    ~H"""
    <div class="card bg-base-100 shadow-sm border border-base-300">
      <div class="card-body p-4">
        <div class="flex items-center gap-2">
          <span class={["text-2xl", node_icon_class(@node.type)]}>{node_icon(@node.type)}</span>
          <div>
            <h3 class="font-bold">{@node.label}</h3>
            <span class={["badge badge-sm", node_type_badge(@node.type)]}>
              {node_type_label(@node.type)}
            </span>
          </div>
        </div>
        <div class="text-sm text-base-content/60 mt-1">
          <span>Zone: {@node.zone.name}</span>
          <span class="mx-1">|</span>
          <span>Danger: {danger_stars(@node.danger_rating)}</span>
        </div>
        <div :if={@node.type == :combat and @node.enemy_type} class="text-sm mt-1">
          <span class="text-error font-semibold">Enemy: {enemy_display_name(@node.enemy_type)}</span>
        </div>
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
        <h2 class="card-title text-warning">
          <span class="text-2xl">&#128722;</span>
          Scrap Trader
        </h2>
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
              >
                Buy
              </button>
            </div>
          </div>
        </div>

        <div class="card-actions justify-center mt-4">
          <button phx-click="leave_node" class="btn btn-sm btn-ghost">
            Leave Shop
          </button>
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
          <button phx-click="leave_node" class="btn btn-sm btn-ghost">
            Leave Repair Bay
          </button>
        </div>
      </div>
    </div>
    """
  end

  # --- Event Panel ---

  attr :node, :map, required: true

  def event_panel(assigns) do
    {text, reward} = random_event(assigns.node)
    assigns = assigns |> assign(:event_text, text) |> assign(:reward, reward)

    ~H"""
    <div class="card bg-base-100 shadow-lg border-2 border-info/30">
      <div class="card-body text-center">
        <h2 class="card-title text-info justify-center">
          <span class="text-2xl">&#10067;</span>
          Discovery
        </h2>
        <p class="text-base-content/80 mt-2">{@event_text}</p>
        <div :if={@reward} class="mt-2">
          <span class="badge badge-info">{@reward}</span>
        </div>
        <div class="card-actions justify-center mt-4">
          <button phx-click="claim_event" class="btn btn-sm btn-info">
            Continue
          </button>
        </div>
      </div>
    </div>
    """
  end

  # --- Helper Functions ---

  defp build_zone_rects(nodes) do
    nodes
    |> Enum.group_by(fn n -> n.zone.name end)
    |> Enum.map(fn {name, zone_nodes} ->
      xs = Enum.map(zone_nodes, fn n -> elem(n.position, 0) end)
      min_x = Enum.min(xs) - 60
      max_x = Enum.max(xs) + 60
      zone = hd(zone_nodes).zone

      %{
        x: max(0, min_x),
        width: min(1000, max_x) - max(0, min_x),
        type: zone.type,
        name: "#{name} (Danger #{zone.danger_rating})"
      }
    end)
    |> Enum.sort_by(& &1.x)
  end

  defp zone_bg_color(:industrial), do: "#f59e0b"
  defp zone_bg_color(:residential), do: "#3b82f6"
  defp zone_bg_color(:commercial), do: "#a855f7"

  defp node_fill(:start, _), do: "#6b7280"
  defp node_fill(:exit, _), do: "#7c3aed"
  defp node_fill(:combat, true), do: "#6b7280"
  defp node_fill(:combat, _), do: "#ef4444"
  defp node_fill(:shop, true), do: "#6b7280"
  defp node_fill(:shop, _), do: "#eab308"
  defp node_fill(:rest, true), do: "#6b7280"
  defp node_fill(:rest, _), do: "#22c55e"
  defp node_fill(:event, true), do: "#6b7280"
  defp node_fill(:event, _), do: "#3b82f6"

  defp node_stroke(:start, _), do: "#9ca3af"
  defp node_stroke(:exit, _), do: "#a78bfa"
  defp node_stroke(_, true), do: "#22c55e"
  defp node_stroke(:combat, _), do: "#f87171"
  defp node_stroke(:shop, _), do: "#fbbf24"
  defp node_stroke(:rest, _), do: "#4ade80"
  defp node_stroke(:event, _), do: "#60a5fa"

  defp node_icon(:start), do: "\u{1F3F3}"
  defp node_icon(:exit), do: "\u{2B50}"
  defp node_icon(:combat), do: "\u{2694}"
  defp node_icon(:shop), do: "\u{1F6D2}"
  defp node_icon(:rest), do: "\u{1F527}"
  defp node_icon(:event), do: "?"

  defp node_icon_class(:combat), do: "text-error"
  defp node_icon_class(:shop), do: "text-warning"
  defp node_icon_class(:rest), do: "text-success"
  defp node_icon_class(:event), do: "text-info"
  defp node_icon_class(_), do: "text-base-content"

  defp node_type_badge(:combat), do: "badge-error"
  defp node_type_badge(:shop), do: "badge-warning"
  defp node_type_badge(:rest), do: "badge-success"
  defp node_type_badge(:event), do: "badge-info"
  defp node_type_badge(:exit), do: "badge-secondary"
  defp node_type_badge(_), do: "badge-ghost"

  defp node_type_label(:start), do: "Start"
  defp node_type_label(:exit), do: "Research Lab"
  defp node_type_label(:combat), do: "Combat"
  defp node_type_label(:shop), do: "Shop"
  defp node_type_label(:rest), do: "Rest"
  defp node_type_label(:event), do: "Event"

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

  defp card_type_short(:weapon), do: "WPN"
  defp card_type_short(:armor), do: "ARM"
  defp card_type_short(:battery), do: "BAT"
  defp card_type_short(:capacitor), do: "CAP"
  defp card_type_short(:chassis), do: "CHS"
  defp card_type_short(:cpu), do: "CPU"
  defp card_type_short(:locomotion), do: "LOC"

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
  defp cpu_ability_summary(%{type: :beam_split}), do: "Split a die into two halves (2x/turn)"
  defp cpu_ability_summary(%{type: :overcharge}), do: "Spend 3+ die for +1 weapon damage"
  defp cpu_ability_summary(%{type: :extra_activation}), do: "Reactivate a used card"
  defp cpu_ability_summary(_), do: "Processing Unit"

  defp scrap_label(:metal), do: "Metal"
  defp scrap_label(:wire), do: "Wire"
  defp scrap_label(:plastic), do: "Plastic"
  defp scrap_label(:grease), do: "Grease"
  defp scrap_label(:chips), do: "Chips"

  @events [
    {"You find a stash of scrap metal hidden in a collapsed storefront.", "+2 Metal", %{metal: 2}},
    {"A broken bot left behind some wiring. Still usable.", "+2 Wire", %{wire: 2}},
    {"You salvage plastic casing from an abandoned kiosk.", "+2 Plastic", %{plastic: 2}},
    {"An oil drum leaks precious lubricant. You collect what you can.", "+2 Grease", %{grease: 2}},
    {"A shattered circuit board yields a few intact chips.", "+1 Chips", %{chips: 1}},
    {"Nothing of note here. The city is quiet, for now.", nil, %{}}
  ]

  def random_event(node) do
    idx = :erlang.phash2(node.id, length(@events))
    {text, reward_label, _resources} = Enum.at(@events, idx)
    {text, reward_label}
  end

  def event_resources(node) do
    idx = :erlang.phash2(node.id, length(@events))
    {_text, _reward_label, resources} = Enum.at(@events, idx)
    resources
  end
end
