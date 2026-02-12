defmodule BotgradeWeb.CombatCardComponents do
  @moduledoc """
  Function components for rendering individual cards in the combat UI.

  Handles card visuals, stats, dice slots, and related helpers.
  Shared card-styling helpers (colors, icons, labels) are public so
  the layout-level CombatComponents module can reuse them.
  """
  use Phoenix.Component
  import BotgradeWeb.CoreComponents, only: [icon: 1]

  alias Botgrade.Game.Card

  # --- Game Card ---

  attr(:card, :map, required: true)
  attr(:phase, :atom, required: true)
  attr(:selected_die, :any, required: true)
  attr(:selected_die_value, :map, default: nil)
  attr(:cpu_targeting, :string, default: nil)
  attr(:cpu_discard_selected, :list, default: [])
  attr(:cpu_targeting_mode, :atom, default: nil)
  attr(:cpu_selected_installed, :string, default: nil)
  attr(:cpu_ability_type, :atom, default: nil)

  def game_card(assigns) do
    interactable = card_interactable?(assigns.card, assigns.phase)
    destroyed = assigns.card.damage == :destroyed

    cpu_selectable =
      not is_nil(assigns.cpu_targeting) and not destroyed and
        card_matches_targeting_mode?(assigns.card, assigns.cpu_targeting_mode, assigns.cpu_ability_type)

    cpu_selected =
      assigns.card.id in assigns.cpu_discard_selected or
        assigns.card.id == assigns.cpu_selected_installed

    assigns =
      assigns
      |> assign(:interactable, interactable)
      |> assign(:destroyed, destroyed)
      |> assign(:cpu_selectable, cpu_selectable)
      |> assign(:cpu_selected, cpu_selected)

    ~H"""
    <div
      class={[
        "rounded-xl border-2 p-3 text-sm flex flex-col gap-2 min-w-[160px] transition-all",
        card_bg(@card.type),
        card_border(@card.type),
        @destroyed && "opacity-30 grayscale",
        not @cpu_selectable and @interactable && "ring-2 ring-primary/40 shadow-lg cursor-pointer",
        not @cpu_selectable and not @interactable and not @destroyed and @phase == :power_up && "opacity-60",
        @cpu_selected && "ring-2 ring-secondary bg-secondary/10",
        @cpu_selectable and not @cpu_selected && "cursor-pointer hover:ring-2 hover:ring-secondary/60"
      ]}
      phx-click={if @cpu_selectable, do: cpu_click_event(@cpu_targeting_mode)}
      phx-value-card-id={if @cpu_selectable, do: @card.id}
    >
      <%!-- Header: icon + name + type badge + info button --%>
      <%!-- Single tag: show inline with title. Multiple tags: separate line. --%>
      <div class={["flex items-start gap-1", @card.damage != :damaged && "justify-between"]}>
        <div class="flex items-center gap-1.5 flex-1 min-w-0">
          <.icon name={card_type_icon(@card.type)} class={["size-4 shrink-0", card_icon_color(@card.type)]} />
          <span class="font-bold leading-tight truncate">{@card.name}</span>
          <%!-- Single badge inline when not damaged --%>
          <span :if={@destroyed and @card.damage != :damaged} class="badge badge-xs badge-error shrink-0">DEAD</span>
          <span :if={not @destroyed and @card.damage != :damaged} class={["badge badge-xs shrink-0", card_badge(@card.type)]}>
            {card_type_label(@card.type)}
          </span>
        </div>
        <button
          :if={not @destroyed}
          phx-click="show_card_info"
          phx-value-card-id={@card.id}
          class="w-5 h-5 rounded-full bg-base-300/40 hover:bg-base-300 flex items-center justify-center shrink-0 cursor-pointer"
          title="Card info"
        >
          <.icon name="hero-information-circle-mini" class="size-3.5 text-base-content/40 hover:text-base-content/70" />
        </button>
      </div>
      <div :if={@card.damage == :damaged} class="flex items-center gap-1">
        <span class="badge badge-xs badge-warning">DMG</span>
        <span :if={@destroyed} class="badge badge-xs badge-error">DEAD</span>
        <span :if={not @destroyed} class={["badge badge-xs", card_badge(@card.type)]}>
          {card_type_label(@card.type)}
        </span>
      </div>

      <%!-- Card HP Bar --%>
      <.card_hp_bar :if={@card.current_hp != nil and not @destroyed} card={@card} />

      <%!-- Stats --%>
      <div :if={not @destroyed} class="text-base-content/70">
        <.card_stats card={@card} />
      </div>

      <%!-- Dice Slots (hidden during CPU targeting to avoid conflicting clicks) --%>
      <div :if={@card.dice_slots != [] and not @destroyed and not @cpu_selectable} class="flex flex-wrap gap-1.5">
        <.dice_slot
          :for={slot <- @card.dice_slots}
          slot={slot}
          card={@card}
          phase={@phase}
          selected_die={@selected_die}
          selected_die_value={@selected_die_value}
        />
      </div>

      <%!-- Battery Activation Button (hidden during CPU targeting) --%>
      <button
        :if={@card.type == :battery and @phase == :power_up and not @destroyed and not @cpu_selectable and @card.properties.remaining_activations > 0 and not Map.get(@card.properties, :activated_this_turn, false)}
        phx-click="activate_battery"
        phx-value-card-id={@card.id}
        class="btn btn-sm btn-primary w-full"
      >
        <.icon name="hero-bolt" class="size-4" />
        Activate
      </button>

      <%!-- Dynamo Activation Button --%>
      <button
        :if={@card.type == :capacitor and Map.get(@card.properties, :capacitor_ability) == :dynamo and @phase == :power_up and not @destroyed and not @cpu_selectable and not Map.get(@card.properties, :activated_this_turn, false) and Enum.any?(@card.dice_slots, &(&1.assigned_die != nil))}
        phx-click="activate_capacitor"
        phx-value-card-id={@card.id}
        class="btn btn-sm btn-info w-full"
      >
        <.icon name="hero-arrow-trending-up" class="size-4" />
        Boost +{Map.get(@card.properties, :boost_amount, 1)}
      </button>
      <span
        :if={@card.type == :capacitor and Map.get(@card.properties, :capacitor_ability) == :dynamo and not @destroyed and Map.get(@card.properties, :activated_this_turn, false)}
        class="text-[10px] text-base-content/50"
      >
        Boosted this turn
      </span>

      <%!-- Activation Result (shown on in-play cards) --%>
      <div :if={@card.last_result} class="flex items-center gap-1.5 text-xs border-t border-base-300/50 pt-1.5 -mb-0.5">
        <div class="flex gap-0.5">
          <span
            :for={die <- @card.last_result.dice}
            class="w-5 h-5 rounded bg-base-300 flex items-center justify-center font-mono font-bold text-[11px]"
          >
            {die.value}
          </span>
        </div>
        <span class="text-base-content/40">=</span>
        <span class={[
          "font-mono font-bold",
          @card.last_result.type == :damage && "text-error",
          @card.last_result.type == :plating && "text-primary",
          @card.last_result.type == :shield && "text-info"
        ]}>
          {result_label(@card.last_result)}
        </span>
      </div>

      <%!-- Used this turn indicator for weapons/armor/utility --%>
      <span
        :if={@card.type in [:weapon, :armor, :utility] and not @destroyed and Map.get(@card.properties, :activated_this_turn, false) == true and not Map.has_key?(@card.properties, :max_activations_per_turn)}
        class="text-[10px] text-base-content/50"
      >
        Used this turn
      </span>
      <span
        :if={@card.type in [:weapon, :armor, :utility] and not @destroyed and Map.has_key?(@card.properties, :max_activations_per_turn)}
        class="text-[10px] text-base-content/50"
      >
        {Map.get(@card.properties, :activations_this_turn, 0)}/{@card.properties.max_activations_per_turn} activations
      </span>

      <%!-- Damage indicator strip --%>
      <div :if={@card.damage == :damaged} class="text-xs text-warning flex items-center gap-1 -mb-1">
        <.icon name="hero-exclamation-triangle-mini" class="size-3.5" />
        Damaged
      </div>
    </div>
    """
  end

  # --- Card HP Bar ---

  attr(:card, :map, required: true)

  defp card_hp_bar(assigns) do
    max_hp = Map.get(assigns.card.properties, :card_hp, 2)
    current_hp = assigns.card.current_hp || 0
    hp_pct = if max_hp > 0, do: current_hp / max_hp * 100, else: 0

    assigns =
      assigns
      |> assign(:max_hp, max_hp)
      |> assign(:hp_pct, hp_pct)

    ~H"""
    <div class="flex items-center gap-1.5">
      <div class="flex-1 bg-base-300 rounded-full h-1.5 overflow-hidden">
        <div
          class={["h-full rounded-full transition-all", hp_bar_color(@card.current_hp, @max_hp)]}
          style={"width: #{@hp_pct}%"}
        />
      </div>
      <span class="text-[10px] font-mono text-base-content/50 shrink-0">
        {@card.current_hp}/{@max_hp}
      </span>
    </div>
    """
  end

  # --- Card Stats ---

  attr(:card, :map, required: true)

  defp card_stats(assigns) do
    ~H"""
    <%= case @card.type do %>
      <% :battery -> %>
        <div class="flex items-center gap-2">
          <%= if @card.damage == :damaged and @card.properties.dice_count > 1 do %>
            <span class="line-through text-base-content/40 font-mono">{@card.properties.dice_count}d{@card.properties.die_sides}</span>
            <span class="text-warning font-mono">{@card.properties.dice_count - 1}d{@card.properties.die_sides}</span>
          <% else %>
            <span class="font-mono">{@card.properties.dice_count}d{@card.properties.die_sides}</span>
            <span :if={@card.damage == :damaged and @card.properties.dice_count == 1} class="text-warning text-[10px]">
              (max {@card.properties.die_sides - 2})
            </span>
          <% end %>
          <span class="text-base-content/50">|</span>
          <.charge_dots
            remaining={@card.properties.remaining_activations}
            max={@card.properties.max_activations}
          />
        </div>
      <% :capacitor -> %>
        <div class="space-y-0.5">
          <span>Stores {length(@card.dice_slots)} {if length(@card.dice_slots) == 1, do: "die", else: "dice"}</span>
          <span :if={@card.damage == :damaged} class="text-warning text-[10px]">
            (max {Card.damaged_capacitor_max_value()})
          </span>
          <div :if={Map.get(@card.properties, :capacitor_ability) == :dynamo} class="text-[10px] text-info">
            Activate: stored die +{Map.get(@card.properties, :boost_amount, 1)} (1x/turn)
          </div>
          <div class="text-[10px] text-base-content/50">Stored dice persist between turns</div>
        </div>
      <% :weapon -> %>
        <div class="space-y-0.5">
          <div class="flex items-center gap-1 flex-wrap">
            <span class={["font-semibold", damage_type_color(@card.properties.damage_type)]}>
              {String.capitalize(to_string(@card.properties.damage_type))}
            </span>
            <span class="font-mono text-error">{weapon_damage_formula(@card)}</span>
          </div>
          <div :if={has_slot_conditions?(@card)} class="text-[10px] text-base-content/50">
            {slot_requirements_label(@card)}
          </div>
          <div :if={Map.has_key?(@card.properties, :dual_mode)} class="text-[10px] text-info">
            {dual_mode_label(@card.properties.dual_mode)}
          </div>
          <div :if={Map.get(@card.properties, :self_damage, 0) > 0} class="text-[10px] text-warning">
            Deals {@card.properties.self_damage} damage to self
          </div>
          <div :if={Map.has_key?(@card.properties, :max_activations_per_turn)} class="text-[10px] text-base-content/50">
            {@card.properties.max_activations_per_turn}x per turn
          </div>
          <div :if={Map.has_key?(@card.properties, :element)} class={["text-[10px] font-semibold", element_color(@card.properties.element)]}>
            {element_label(@card.properties.element)} element
          </div>
          <div :if={Map.get(@card.properties, :random_element, false)} class="text-[10px] font-semibold text-accent">
            Random element
          </div>
        </div>
      <% :armor -> %>
        <div class="space-y-0.5">
          <div class="flex items-center gap-1">
            <span class="font-semibold">{String.capitalize(to_string(@card.properties.armor_type))}</span>
            <span class={["font-mono", armor_type_color(@card.properties.armor_type)]}>
              {armor_formula(@card)}
            </span>
          </div>
          <div :if={has_slot_conditions?(@card)} class="text-[10px] text-base-content/50">
            {slot_requirements_label(@card)}
          </div>
        </div>
      <% :locomotion -> %>
        <span>Speed <span class="font-mono text-success">+{@card.properties.speed_base}</span></span>
      <% :chassis -> %>
        <div class="space-y-0.5">
          <div class="flex items-center gap-1">
            <.icon name="hero-heart-mini" class="size-3.5 text-error" />
            <span class="font-mono">{Map.get(@card.properties, :card_hp, 0)} HP</span>
          </div>
          <div :if={Map.get(@card.properties, :chassis_ability) == :ablative_ceramic} class="text-[10px] text-info">
            Absorbs hits targeting CPU
          </div>
        </div>
      <% :cpu -> %>
        <div class="space-y-0.5">
          <div class="flex items-center gap-1">
            <.icon name="hero-cpu-chip-mini" class="size-3.5 text-secondary" />
            <span class="font-semibold text-[10px]">{cpu_ability_label(@card.properties[:cpu_ability])}</span>
          </div>
          <div class="text-[10px] text-base-content/50">
            {cpu_ability_description(@card.properties[:cpu_ability])}
          </div>
        </div>
      <% :utility -> %>
        <div class="space-y-0.5">
          <div class="flex items-center gap-1">
            <.icon name="hero-wrench-mini" class="size-3.5 text-accent" />
            <span class="font-semibold">{utility_ability_label(@card.properties[:utility_ability])}</span>
          </div>
          <div class="text-[10px] text-base-content/50">
            {utility_ability_description(@card.properties[:utility_ability])}
          </div>
          <div :if={has_slot_conditions?(@card)} class="text-[10px] text-base-content/50">
            {slot_requirements_label(@card)}
          </div>
          <div :if={Map.has_key?(@card.properties, :max_activations_per_turn)} class="text-[10px] text-base-content/50">
            {@card.properties.max_activations_per_turn}x per turn
          </div>
        </div>
    <% end %>
    """
  end

  # --- Card Detail Stats (for scavenge panel) ---

  attr(:card, :map, required: true)

  def card_detail_stats(assigns) do
    ~H"""
    <div class="space-y-1">
      <.card_stats card={@card} />
      <div :if={@card.damage == :damaged} class="text-[10px] text-warning bg-warning/10 rounded px-1.5 py-0.5">
        <.icon name="hero-exclamation-triangle-mini" class="size-3 inline" />
        {damage_penalty_description(@card)}
      </div>
      <div class="text-[10px] text-base-content/50">
        Card HP: {Map.get(@card.properties, :card_hp, 2)}
      </div>
    </div>
    """
  end

  # --- Charge Dots ---

  attr(:remaining, :integer, required: true)
  attr(:max, :integer, required: true)

  defp charge_dots(assigns) do
    ~H"""
    <div class="flex items-center gap-0.5" title={"#{@remaining}/#{@max} charges"}>
      <span
        :for={i <- 1..@max}
        class={[
          "w-2 h-2 rounded-full",
          i <= @remaining && "bg-warning",
          i > @remaining && "bg-base-300"
        ]}
      />
    </div>
    """
  end

  # --- Dice Slot ---

  attr(:slot, :map, required: true)
  attr(:card, :map, required: true)
  attr(:phase, :atom, required: true)
  attr(:selected_die, :any, required: true)
  attr(:selected_die_value, :map, default: nil)

  defp dice_slot(assigns) do
    compatible =
      if assigns.selected_die_value do
        Card.meets_condition?(assigns.slot.condition, assigns.selected_die_value.value)
      else
        true
      end

    assigns = assign(assigns, :compatible, compatible)

    ~H"""
    <div :if={@slot.assigned_die != nil} class="relative group">
      <div
        phx-click={if @phase == :power_up, do: "unassign_die"}
        phx-value-card-id={if @phase == :power_up, do: @card.id}
        phx-value-slot-id={if @phase == :power_up, do: @slot.id}
        class={[
          "w-10 h-10 rounded-lg border-2 border-success bg-success/15 flex flex-col items-center justify-center font-mono",
          @phase == :power_up && "cursor-pointer hover:border-error hover:bg-error/10"
        ]}
      >
        <span class="text-lg font-bold leading-none">{@slot.assigned_die.value}</span>
        <span class="text-[8px] opacity-50 leading-none">d{@slot.assigned_die.sides}</span>
      </div>
      <span :if={@phase == :power_up} class="absolute -top-1 -right-1 bg-error text-error-content rounded-full w-4 h-4 text-[10px] flex items-center justify-center opacity-0 group-hover:opacity-100 transition-opacity pointer-events-none">
        x
      </span>
    </div>

    <%!-- Locked slot (Fused mechanic) --%>
    <div :if={@slot.assigned_die == nil and Map.get(@slot, :locked, false)}>
      <button
        :if={@phase == :power_up and @selected_die != nil}
        phx-click="assign_die"
        phx-value-card-id={@card.id}
        phx-value-slot-id={@slot.id}
        class="w-10 h-10 rounded-lg border-2 border-violet-500 bg-violet-500/20 flex flex-col items-center justify-center text-[10px] animate-pulse cursor-pointer"
      >
        <.icon name="hero-lock-closed-mini" class="size-4 text-violet-500" />
      </button>
      <div
        :if={not (@phase == :power_up and @selected_die != nil)}
        class="w-10 h-10 rounded-lg border-2 border-violet-500 bg-violet-500/10 flex items-center justify-center"
      >
        <.icon name="hero-lock-closed-mini" class="size-4 text-violet-400" />
      </div>
    </div>

    <%!-- Normal empty slot --%>
    <div :if={@slot.assigned_die == nil and not Map.get(@slot, :locked, false)}>
      <button
        :if={@phase == :power_up and @selected_die != nil}
        phx-click="assign_die"
        phx-value-card-id={@card.id}
        phx-value-slot-id={@slot.id}
        class={[
          "w-10 h-10 rounded-lg border-2 border-dashed flex flex-col items-center justify-center text-[10px] transition-all",
          @compatible && "border-primary bg-primary/10 hover:bg-primary/20 cursor-pointer animate-pulse",
          not @compatible && "border-base-300 opacity-40 cursor-not-allowed"
        ]}
        disabled={not @compatible}
      >
        <span :if={@slot.condition} class={[@compatible && "text-primary", not @compatible && "text-error"]}>
          {condition_label(@slot.condition)}
        </span>
        <span :if={@slot.condition == nil} class="text-primary">+</span>
      </button>

      <div
        :if={not (@phase == :power_up and @selected_die != nil)}
        class="w-10 h-10 rounded-lg border-2 border-dashed border-base-300 flex flex-col items-center justify-center text-[10px] text-base-content/40"
      >
        <span :if={@slot.condition}>{condition_label(@slot.condition)}</span>
        <span :if={@slot.condition == nil}>-</span>
      </div>
    </div>
    """
  end

  # --- Card Info Panel (bottom drawer) ---

  attr(:card, :map, default: nil)

  def card_info_panel(assigns) do
    ~H"""
    <div
      :if={@card}
      id="card-info-panel"
      class="fixed inset-0 z-50 flex flex-col justify-end"
    >
      <%!-- Backdrop --%>
      <div class="absolute inset-0 bg-black/40" phx-click="close_card_info" />

      <%!-- Panel --%>
      <div
        class="relative max-h-[70vh] overflow-y-auto bg-base-100 rounded-t-2xl border-t-2 border-base-300 shadow-2xl"
        style="animation: slide-up 0.2s ease-out"
      >
        <div class="p-4 pb-8 max-w-2xl mx-auto">
          <%!-- Drag handle --%>
          <div class="flex justify-center mb-3">
            <div class="w-10 h-1 rounded-full bg-base-300" />
          </div>

          <%!-- Close button --%>
          <button
            phx-click="close_card_info"
            class="absolute top-3 right-3 btn btn-ghost btn-sm btn-circle"
          >
            <.icon name="hero-x-mark" class="size-5" />
          </button>

          <%!-- Card Header --%>
          <div class="flex items-center gap-2 mb-4">
            <.icon name={card_type_icon(@card.type)} class={["size-6", card_icon_color(@card.type)]} />
            <h3 class="text-lg font-bold">{@card.name}</h3>
            <span class={["badge", card_badge(@card.type)]}>{card_type_label(@card.type)}</span>
          </div>

          <div class="space-y-3">
            <%!-- What This Card Does --%>
            <div class="bg-base-200 rounded-xl p-3">
              <h4 class="text-xs font-bold text-base-content/60 uppercase tracking-wide mb-1">What it does</h4>
              <p class="text-sm">{card_type_explanation(@card.type)}</p>
            </div>

            <%!-- Stats & Details --%>
            <div class="bg-base-200 rounded-xl p-3">
              <h4 class="text-xs font-bold text-base-content/60 uppercase tracking-wide mb-1">Details</h4>
              <.card_property_details card={@card} />
            </div>

            <%!-- How to Use --%>
            <div class="bg-base-200 rounded-xl p-3">
              <h4 class="text-xs font-bold text-base-content/60 uppercase tracking-wide mb-1">How to use</h4>
              <p class="text-sm text-base-content/70">{card_usage_hint(@card)}</p>
            </div>
          </div>
        </div>
      </div>
    </div>
    """
  end

  # --- Card Property Details (for info panel) ---

  attr(:card, :map, required: true)

  defp card_property_details(assigns) do
    ~H"""
    <div class="text-sm space-y-1">
      <%= case @card.type do %>
        <% :battery -> %>
          <div class="flex items-center gap-2">
            <span class="text-base-content/50">Dice pool:</span>
            <span class="font-mono font-semibold">{@card.properties.dice_count}d{@card.properties.die_sides}</span>
          </div>
          <div class="flex items-center gap-2">
            <span class="text-base-content/50">Charges:</span>
            <span class="font-mono">{@card.properties.remaining_activations}/{@card.properties.max_activations}</span>
          </div>
          <div class="flex items-center gap-2">
            <span class="text-base-content/50">Card HP:</span>
            <span class="font-mono">{Map.get(@card.properties, :card_hp, 2)}</span>
          </div>
        <% :capacitor -> %>
          <div class="flex items-center gap-2">
            <span class="text-base-content/50">Storage slots:</span>
            <span class="font-mono font-semibold">{length(@card.dice_slots)}</span>
          </div>
          <div :if={Map.get(@card.properties, :capacitor_ability) == :dynamo} class="flex items-center gap-2">
            <span class="text-base-content/50">Ability:</span>
            <span class="font-semibold text-info">Dynamo — boost stored die by +{Map.get(@card.properties, :boost_amount, 1)}</span>
          </div>
          <div class="flex items-center gap-2">
            <span class="text-base-content/50">Card HP:</span>
            <span class="font-mono">{Map.get(@card.properties, :card_hp, 2)}</span>
          </div>
        <% :weapon -> %>
          <div class="flex items-center gap-2">
            <span class="text-base-content/50">Damage type:</span>
            <span class={["font-semibold", damage_type_color(@card.properties.damage_type)]}>
              {String.capitalize(to_string(@card.properties.damage_type))}
            </span>
          </div>
          <div class="flex items-center gap-2">
            <span class="text-base-content/50">Damage formula:</span>
            <span class="font-mono text-error">{weapon_damage_formula(@card)}</span>
          </div>
          <div class="flex items-center gap-2">
            <span class="text-base-content/50">Dice slots:</span>
            <span class="font-mono">{length(@card.dice_slots)}</span>
          </div>
          <div :if={has_slot_conditions?(@card)} class="flex items-center gap-2">
            <span class="text-base-content/50">Slot requirement:</span>
            <span class="font-semibold">{slot_requirements_label(@card)}</span>
          </div>
          <div :if={Map.has_key?(@card.properties, :dual_mode)} class="flex items-center gap-2">
            <span class="text-base-content/50">Dual mode:</span>
            <span class="text-info">{dual_mode_label(@card.properties.dual_mode)}</span>
          </div>
          <div :if={Map.get(@card.properties, :self_damage, 0) > 0} class="flex items-center gap-2">
            <span class="text-base-content/50">Self damage:</span>
            <span class="text-warning">{@card.properties.self_damage} per use</span>
          </div>
          <div :if={Map.get(@card.properties, :escalating, false)} class="flex items-center gap-2">
            <span class="text-base-content/50">Escalating:</span>
            <span class="text-warning">+1 damage per weapon activated before it</span>
          </div>
          <div :if={Map.get(@card.properties, :damage_multiplier, 1) > 1} class="flex items-center gap-2">
            <span class="text-base-content/50">Multiplier:</span>
            <span class="text-error font-semibold">x{@card.properties.damage_multiplier}</span>
          </div>
          <div :if={Map.has_key?(@card.properties, :element)} class="flex items-center gap-2">
            <span class="text-base-content/50">Element:</span>
            <span class={["font-semibold", element_color(@card.properties.element)]}>
              {element_label(@card.properties.element)} ({@card.properties.element_stacks} stack{if @card.properties.element_stacks != 1, do: "s"})
            </span>
          </div>
          <div :if={Map.get(@card.properties, :random_element, false)} class="flex items-center gap-2">
            <span class="text-base-content/50">Element:</span>
            <span class="text-accent font-semibold">Random each hit</span>
          </div>
          <div :if={Map.has_key?(@card.properties, :max_activations_per_turn)} class="flex items-center gap-2">
            <span class="text-base-content/50">Uses per turn:</span>
            <span class="font-mono">{@card.properties.max_activations_per_turn}</span>
          </div>
          <div :if={Map.has_key?(@card.properties, :end_of_turn_effect)} class="flex items-center gap-2">
            <span class="text-base-content/50">Passive:</span>
            <span class="text-info">{end_of_turn_label(@card.properties.end_of_turn_effect)}</span>
          </div>
          <div class="flex items-center gap-2">
            <span class="text-base-content/50">Card HP:</span>
            <span class="font-mono">{Map.get(@card.properties, :card_hp, 3)}</span>
          </div>
        <% :armor -> %>
          <div class="flex items-center gap-2">
            <span class="text-base-content/50">Type:</span>
            <span class="font-semibold">{String.capitalize(to_string(@card.properties.armor_type))}</span>
          </div>
          <div class="flex items-center gap-2">
            <span class="text-base-content/50">Defense formula:</span>
            <span class={["font-mono", armor_type_color(@card.properties.armor_type)]}>{armor_formula(@card)}</span>
          </div>
          <div :if={has_slot_conditions?(@card)} class="flex items-center gap-2">
            <span class="text-base-content/50">Slot requirement:</span>
            <span class="font-semibold">{slot_requirements_label(@card)}</span>
          </div>
          <div class="flex items-center gap-2">
            <span class="text-base-content/50">Card HP:</span>
            <span class="font-mono">{Map.get(@card.properties, :card_hp, 3)}</span>
          </div>
        <% :locomotion -> %>
          <div class="flex items-center gap-2">
            <span class="text-base-content/50">Speed bonus:</span>
            <span class="font-mono text-success">+{@card.properties.speed_base}</span>
          </div>
          <div class="flex items-center gap-2">
            <span class="text-base-content/50">Card HP:</span>
            <span class="font-mono">{Map.get(@card.properties, :card_hp, 2)}</span>
          </div>
        <% :chassis -> %>
          <div class="flex items-center gap-2">
            <span class="text-base-content/50">Hit points:</span>
            <span class="font-mono">{Map.get(@card.properties, :card_hp, 0)} HP</span>
          </div>
          <div :if={Map.get(@card.properties, :chassis_ability) == :ablative_ceramic} class="flex items-center gap-2">
            <span class="text-base-content/50">Ability:</span>
            <span class="text-info font-semibold">Absorbs hits targeting CPU</span>
          </div>
        <% :cpu -> %>
          <div class="flex items-center gap-2">
            <span class="text-base-content/50">Ability:</span>
            <span class="font-semibold text-secondary">{cpu_ability_label(@card.properties[:cpu_ability])}</span>
          </div>
          <div class="flex items-center gap-2">
            <span class="text-base-content/50">Effect:</span>
            <span>{cpu_ability_description(@card.properties[:cpu_ability])}</span>
          </div>
          <div class="flex items-center gap-2">
            <span class="text-base-content/50">Card HP:</span>
            <span class="font-mono">{Map.get(@card.properties, :card_hp, 2)}</span>
          </div>
        <% :utility -> %>
          <div class="flex items-center gap-2">
            <span class="text-base-content/50">Ability:</span>
            <span class="font-semibold text-accent">{utility_ability_label(@card.properties[:utility_ability])}</span>
          </div>
          <div class="flex items-center gap-2">
            <span class="text-base-content/50">Effect:</span>
            <span>{utility_ability_description(@card.properties[:utility_ability])}</span>
          </div>
          <div :if={has_slot_conditions?(@card)} class="flex items-center gap-2">
            <span class="text-base-content/50">Slot requirement:</span>
            <span class="font-semibold">{slot_requirements_label(@card)}</span>
          </div>
          <div :if={Map.has_key?(@card.properties, :max_activations_per_turn)} class="flex items-center gap-2">
            <span class="text-base-content/50">Uses per turn:</span>
            <span class="font-mono">{@card.properties.max_activations_per_turn}</span>
          </div>
          <div class="flex items-center gap-2">
            <span class="text-base-content/50">Card HP:</span>
            <span class="font-mono">{Map.get(@card.properties, :card_hp, 2)}</span>
          </div>
      <% end %>
      <div :if={@card.damage == :damaged} class="mt-2 text-warning bg-warning/10 rounded px-2 py-1">
        <.icon name="hero-exclamation-triangle-mini" class="size-3 inline" />
        {damage_penalty_description(@card)}
      </div>
    </div>
    """
  end

  # ===================================================================
  # Shared card-styling helpers (public for use by CombatComponents)
  # ===================================================================

  def card_type_icon(:battery), do: "hero-bolt"
  def card_type_icon(:capacitor), do: "hero-circle-stack"
  def card_type_icon(:weapon), do: "hero-fire"
  def card_type_icon(:armor), do: "hero-shield-check"
  def card_type_icon(:locomotion), do: "hero-arrow-trending-up"
  def card_type_icon(:chassis), do: "hero-cube"
  def card_type_icon(:cpu), do: "hero-cpu-chip"
  def card_type_icon(:utility), do: "hero-wrench"

  def card_icon_color(:battery), do: "text-warning"
  def card_icon_color(:capacitor), do: "text-info"
  def card_icon_color(:weapon), do: "text-error"
  def card_icon_color(:armor), do: "text-primary"
  def card_icon_color(:locomotion), do: "text-success"
  def card_icon_color(:chassis), do: "text-base-content/50"
  def card_icon_color(:cpu), do: "text-secondary"
  def card_icon_color(:utility), do: "text-accent"

  def card_bg(:battery), do: "bg-gradient-to-b from-warning/10 to-transparent"
  def card_bg(:capacitor), do: "bg-gradient-to-b from-info/10 to-transparent"
  def card_bg(:weapon), do: "bg-gradient-to-b from-error/10 to-transparent"
  def card_bg(:armor), do: "bg-gradient-to-b from-primary/10 to-transparent"
  def card_bg(:locomotion), do: "bg-gradient-to-b from-success/10 to-transparent"
  def card_bg(:chassis), do: "bg-gradient-to-b from-base-300/20 to-transparent"
  def card_bg(:cpu), do: "bg-gradient-to-b from-secondary/10 to-transparent"
  def card_bg(:utility), do: "bg-gradient-to-b from-accent/10 to-transparent"

  def card_border(:battery), do: "border-warning/50"
  def card_border(:capacitor), do: "border-info/50"
  def card_border(:weapon), do: "border-error/50"
  def card_border(:armor), do: "border-primary/50"
  def card_border(:locomotion), do: "border-success/50"
  def card_border(:chassis), do: "border-base-300"
  def card_border(:cpu), do: "border-secondary/50"
  def card_border(:utility), do: "border-accent/50"

  def card_badge(:battery), do: "badge-warning"
  def card_badge(:capacitor), do: "badge-info"
  def card_badge(:weapon), do: "badge-error"
  def card_badge(:armor), do: "badge-primary"
  def card_badge(:locomotion), do: "badge-success"
  def card_badge(:chassis), do: "badge-ghost"
  def card_badge(:cpu), do: "badge-secondary"
  def card_badge(:utility), do: "badge-accent"

  def card_type_label(:battery), do: "Battery"
  def card_type_label(:capacitor), do: "Capacitor"
  def card_type_label(:weapon), do: "Weapon"
  def card_type_label(:armor), do: "Armor"
  def card_type_label(:locomotion), do: "Movement"
  def card_type_label(:chassis), do: "Chassis"
  def card_type_label(:cpu), do: "CPU"
  def card_type_label(:utility), do: "Utility"

  def hp_bar_color(current, total) when is_number(current) and is_number(total) and total > 0 and current > total * 0.5, do: "bg-success"
  def hp_bar_color(current, total) when is_number(current) and is_number(total) and total > 0 and current > total * 0.25, do: "bg-warning"
  def hp_bar_color(_current, _total), do: "bg-error"

  # ===================================================================
  # Private helpers
  # ===================================================================

  defp card_interactable?(%{damage: :destroyed}, _phase), do: false

  defp card_interactable?(card, :power_up) do
    cond do
      card.type == :battery and
        card.properties.remaining_activations > 0 and
          not Map.get(card.properties, :activated_this_turn, false) ->
        true

      card.type == :capacitor and Map.get(card.properties, :capacitor_ability) == :dynamo and
        not Map.get(card.properties, :activated_this_turn, false) and
          Enum.any?(card.dice_slots, &(&1.assigned_die != nil)) ->
        true

      card.type in [:weapon, :armor, :utility] and card_fully_activated_ui?(card) ->
        false

      card.dice_slots != [] and Enum.any?(card.dice_slots, &(&1.assigned_die == nil)) ->
        true

      true ->
        false
    end
  end

  defp card_interactable?(_card, _phase), do: false

  defp card_fully_activated_ui?(card) do
    max_per_turn = Map.get(card.properties, :max_activations_per_turn)

    if max_per_turn do
      Map.get(card.properties, :activations_this_turn, 0) >= max_per_turn
    else
      Map.get(card.properties, :activated_this_turn, false)
    end
  end

  defp card_matches_targeting_mode?(card, :select_hand_cards, _ability_type) do
    not Map.get(card.properties, :activated_this_turn, false)
  end

  defp card_matches_targeting_mode?(card, :select_installed_card, :reflex_block) do
    card.type == :armor
  end

  defp card_matches_targeting_mode?(card, :select_installed_card, :siphon_power) do
    card.type == :battery and
      card.properties.remaining_activations < card.properties.max_activations
  end

  defp card_matches_targeting_mode?(card, :select_installed_card, :extra_activation) do
    card.type in [:weapon, :armor, :utility] and
      Map.get(card.properties, :activated_this_turn, false)
  end

  defp card_matches_targeting_mode?(_card, _, _), do: false

  defp cpu_click_event(:select_hand_cards), do: "toggle_cpu_discard"
  defp cpu_click_event(:select_installed_card), do: "select_cpu_target_card"
  defp cpu_click_event(_), do: nil

  defp condition_label({:min, n}), do: "#{n}+"
  defp condition_label({:max, n}), do: "#{n}-"
  defp condition_label({:exact, n}), do: "=#{n}"
  defp condition_label(:even), do: "even"
  defp condition_label(:odd), do: "odd"
  defp condition_label(nil), do: ""

  defp result_label(%{type: :damage, value: v}), do: "#{v} dmg"
  defp result_label(%{type: :plating, value: v}), do: "+#{v} plating"
  defp result_label(%{type: :shield, value: v}), do: "+#{v} shield"
  defp result_label(%{type: :utility, ability: :beam_split}), do: "split"
  defp result_label(%{type: :utility, ability: :overcharge}), do: "+1 dmg"
  defp result_label(%{type: :utility, ability: :quantum_tumbler}), do: "rerolled"
  defp result_label(%{type: :utility, ability: :internal_servo}), do: "drew"
  defp result_label(%{type: :utility}), do: "activated"

  defp damage_type_color(:kinetic), do: "text-amber-500"
  defp damage_type_color(:energy), do: "text-info"
  defp damage_type_color(:plasma), do: "text-fuchsia-500"
  defp damage_type_color(_), do: ""

  defp weapon_damage_formula(card) do
    base = card.properties.damage_base
    slot_count = length(card.dice_slots)
    multiplier = Map.get(card.properties, :damage_multiplier, 1)

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

    extra =
      cond do
        Map.get(card.properties, :escalating, false) -> " (+1/wpn)"
        true -> ""
      end

    "#{dice_part}#{base_part}#{extra}"
  end

  defp armor_formula(card) do
    base = card.properties.shield_base
    slot_count = length(card.dice_slots)

    dice_part = if slot_count == 1, do: "die", else: "#{slot_count} dice"
    base_part = if base > 0, do: " + #{base}", else: ""

    "#{dice_part}#{base_part}"
  end

  defp armor_type_color(:plating), do: "text-primary"
  defp armor_type_color(:shield), do: "text-info"
  defp armor_type_color(_), do: ""

  defp has_slot_conditions?(card) do
    Enum.any?(card.dice_slots, fn slot -> slot.condition != nil end)
  end

  defp slot_requirements_label(card) do
    conditions =
      card.dice_slots
      |> Enum.filter(& &1.condition)
      |> Enum.map(&condition_label(&1.condition))
      |> Enum.uniq()

    case conditions do
      [] -> ""
      [c] -> "Requires: #{c}"
      cs -> "Requires: #{Enum.join(cs, ", ")}"
    end
  end

  defp dual_mode_label(%{condition: cond, armor_type: type, shield_base: base}) do
    type_name = String.capitalize(to_string(type))
    cond_text = condition_label(cond)
    base_text = if base > 0, do: " (base +#{base})", else: ""
    "If #{cond_text}: becomes #{type_name}#{base_text}"
  end

  defp cpu_ability_label(%{type: :discard_draw, discard_count: d, draw_count: r}),
    do: "Discard #{d}, Draw #{r}"

  defp cpu_ability_label(%{type: :reflex_block}), do: "Reflex Block"
  defp cpu_ability_label(%{type: :target_lock}), do: "Target Lock"
  defp cpu_ability_label(%{type: :overclock_battery}), do: "Overclock"
  defp cpu_ability_label(%{type: :siphon_power}), do: "Siphon Power"
  defp cpu_ability_label(%{type: :extra_activation}), do: "Boost"
  defp cpu_ability_label(_), do: "Processing Unit"

  defp cpu_ability_description(%{type: :discard_draw, discard_count: d, draw_count: r}),
    do: "Discard #{d} card(s), then draw #{r}"

  defp cpu_ability_description(%{type: :reflex_block}),
    do: "Boost an armor card's shield by +1"

  defp cpu_ability_description(%{type: :target_lock}),
    do: "Next weapon bypasses all defenses"

  defp cpu_ability_description(%{type: :overclock_battery}),
    do: "Next battery can activate twice"

  defp cpu_ability_description(%{type: :siphon_power}),
    do: "Spend 2 shield to restore a battery charge"

  defp cpu_ability_description(%{type: :extra_activation}),
    do: "Give a used card an extra activation"

  defp cpu_ability_description(_), do: ""

  defp utility_ability_label(:beam_split), do: "Beam Split"
  defp utility_ability_label(:overcharge), do: "Overcharge"
  defp utility_ability_label(:quantum_tumbler), do: "Reroll"
  defp utility_ability_label(:internal_servo), do: "Draw"
  defp utility_ability_label(_), do: "Utility"

  defp utility_ability_description(:beam_split), do: "Split a die into two halves"
  defp utility_ability_description(:overcharge), do: "Weapons deal +1 damage this turn"
  defp utility_ability_description(:quantum_tumbler), do: "Reroll the die"
  defp utility_ability_description(:internal_servo), do: "Draw die value + 1 cards"
  defp utility_ability_description(_), do: ""

  defp damage_penalty_description(%{type: :battery} = card) do
    count = card.properties.dice_count
    if count > 1 do
      "Damaged: rolls #{count - 1}d#{card.properties.die_sides} instead of #{count}d#{card.properties.die_sides}"
    else
      "Damaged: die capped at #{card.properties.die_sides - 2}"
    end
  end

  defp damage_penalty_description(%{type: :capacitor}),
    do: "Damaged: stored dice capped at #{Card.damaged_capacitor_max_value()}"

  defp damage_penalty_description(%{type: :weapon}), do: "Damaged: total damage halved"
  defp damage_penalty_description(%{type: :armor}), do: "Damaged: total defense halved"
  defp damage_penalty_description(%{type: :cpu}), do: "Damaged: 1-in-3 chance of malfunction"
  defp damage_penalty_description(%{type: :utility}), do: "Damaged: reduced effectiveness"
  defp damage_penalty_description(_card), do: "Damaged: reduced effectiveness"

  defp element_color(:fire), do: "text-orange-500"
  defp element_color(:ice), do: "text-cyan-400"
  defp element_color(:magnetic), do: "text-violet-500"
  defp element_color(:dark), do: "text-gray-400"
  defp element_color(:water), do: "text-blue-500"
  defp element_color(_), do: "text-base-content/60"

  defp card_type_explanation(:battery),
    do: "Batteries power your robot. Activate them to roll dice and add them to your dice pool. Each battery has limited charges — once depleted, it can't generate more dice."

  defp card_type_explanation(:capacitor),
    do: "Capacitors store dice between turns. Drag dice into their slots to save them for later. Stored dice persist even when your turn ends, letting you stockpile for a big play."

  defp card_type_explanation(:weapon),
    do: "Weapons deal damage to the enemy. Assign dice from your pool into their slots to power them. Damage is calculated from the dice values plus any base damage. Different damage types interact differently with enemy defenses."

  defp card_type_explanation(:armor),
    do: "Armor protects your robot from enemy attacks. Assign dice to generate plating or shields. Plating is permanent until destroyed. Shields refresh each turn but must be re-powered."

  defp card_type_explanation(:locomotion),
    do: "Locomotion determines your robot's speed. The faster robot attacks first each turn. Assign a die to boost your speed for the round."

  defp card_type_explanation(:chassis),
    do: "Chassis cards are your robot's structural hit points. They have no dice slots — they just provide HP. When all chassis HP reaches zero, your robot is destroyed."

  defp card_type_explanation(:cpu),
    do: "CPUs provide special abilities you can activate once per turn. They don't use dice slots — instead, they trigger unique effects like discarding and drawing cards, boosting defenses, or locking onto targets."

  defp card_type_explanation(:utility),
    do: "Utility cards provide special support abilities. Assign a die to activate their effect. They can manipulate dice, boost damage, draw cards, or split dice into multiple smaller values."

  defp card_usage_hint(%{type: :battery} = card) do
    charges = card.properties.remaining_activations
    dice = card.properties.dice_count
    sides = card.properties.die_sides

    cond do
      charges == 0 -> "This battery is depleted — no charges remaining."
      charges <= 2 -> "Only #{charges} charge#{if charges == 1, do: "", else: "s"} left. Use wisely! Click 'Activate' during the power-up phase to roll #{dice}d#{sides}."
      true -> "Click 'Activate' during the power-up phase to roll #{dice}d#{sides} and add the results to your dice pool. You have #{charges} charges remaining."
    end
  end

  defp card_usage_hint(%{type: :capacitor} = card) do
    if Map.get(card.properties, :capacitor_ability) == :dynamo do
      "Store a die by dragging it into the slot. Then click 'Boost' to increase the stored die's value by +#{Map.get(card.properties, :boost_amount, 1)}. Great for turning a mediocre die into a strong one."
    else
      slots = length(card.dice_slots)
      "Drag dice from your pool into the #{slots} storage slot#{if slots == 1, do: "", else: "s"}. These dice carry over between turns, so you can save high rolls for when you need them most."
    end
  end

  defp card_usage_hint(%{type: :weapon} = card) do
    slots = length(card.dice_slots)
    type_name = to_string(card.properties.damage_type)

    base =
      if slots == 0 do
        "This weapon activates automatically at end of turn — no dice needed."
      else
        cond do
          has_slot_conditions?(card) -> "Assign #{slots} die to the slot#{if slots == 1, do: "", else: "s"}. This weapon has dice requirements — check the slot labels for which values are accepted."
          true -> "Assign #{slots} die to the slot#{if slots == 1, do: "", else: "s"} to deal #{type_name} damage. Higher dice values mean more damage."
        end
      end

    extra =
      cond do
        Map.get(card.properties, :self_damage, 0) > 0 -> " Warning: this weapon damages itself when fired."
        Map.get(card.properties, :escalating, false) -> " Bonus: deals extra damage for each weapon you've already activated this turn."
        Map.has_key?(card.properties, :dual_mode) -> " This weapon can also act as a shield under certain conditions."
        Map.has_key?(card.properties, :element) -> " Applies #{element_label(card.properties.element)} elemental stacks on hit."
        true -> ""
      end

    base <> extra
  end

  defp card_usage_hint(%{type: :armor} = card) do
    case card.properties.armor_type do
      :plating ->
        "Assign a die to generate plating points. Plating is permanent and absorbs damage until destroyed. " <>
          if(has_slot_conditions?(card), do: "This armor has dice requirements — check the slot label.", else: "Any die value works — higher is better.")
      :shield ->
        "Assign a die to generate shield points. Shields reset each turn, so you need to re-power them. " <>
          if(has_slot_conditions?(card), do: "This armor has dice requirements — check the slot label.", else: "Any die value works — higher is better.")
    end
  end

  defp card_usage_hint(%{type: :locomotion}) do
    "Assign a die to boost your speed this turn. The robot with higher total speed attacks first. Even a small speed advantage can mean the difference between destroying a key enemy component before it fires."
  end

  defp card_usage_hint(%{type: :chassis} = card) do
    hp = Map.get(card.properties, :card_hp, 0)
    ability = Map.get(card.properties, :chassis_ability)

    base = "This chassis provides #{hp} HP to your robot's total. It has no active ability — it's purely structural."

    if ability == :ablative_ceramic do
      base <> " Special: absorbs hits that would target your CPU, protecting your abilities."
    else
      base
    end
  end

  defp card_usage_hint(%{type: :cpu} = card) do
    case card.properties[:cpu_ability] do
      %{type: :discard_draw, discard_count: d, draw_count: r} ->
        "Click 'Activate' on your CPU during the power-up phase. Select #{d} card#{if d == 1, do: "", else: "s"} from your hand to discard, then draw #{r} new card#{if r == 1, do: "", else: "s"}. Use this to cycle bad cards for better ones."
      %{type: :reflex_block} ->
        "Click 'Activate' then select an armor card to boost. Adds +1 to its shield value this turn. Great for shoring up defenses when you expect a big hit."
      %{type: :target_lock} ->
        "Click 'Activate' to lock on. Your next weapon attack will bypass all enemy plating and shields, hitting their components directly."
      %{type: :overclock_battery} ->
        "Click 'Activate' to overclock. Your next battery activation will trigger twice, giving you double the dice."
      %{type: :siphon_power} ->
        "Click 'Activate' then select a depleted battery. Spend 2 shield points to restore one charge to the battery."
      %{type: :extra_activation} ->
        "Click 'Activate' then select a card that was already used this turn. It gets an extra activation, letting you use it again."
      _ ->
        "Click 'Activate' on your CPU during the power-up phase to use its special ability."
    end
  end

  defp card_usage_hint(%{type: :utility} = card) do
    case card.properties[:utility_ability] do
      :beam_split -> "Assign a die to split it into two dice, each with half the value (rounded down and up). Great for filling multiple weapon slots from a single high die."
      :overcharge -> "Assign a die to activate. All your weapons deal +1 damage this turn. Stack multiple activations for even more bonus damage."
      :quantum_tumbler -> "Assign a die to reroll it, getting a new random value. Use this on low rolls to try for something better."
      :internal_servo -> "Assign a die to draw cards equal to the die value + 1. Low dice are actually great here since you draw regardless."
      _ -> "Assign a die to the slot to activate this utility's special ability."
    end
  end

  defp end_of_turn_label(:plasma_lobber), do: "Fires automatically at end of turn (random damage 1-3)"
  defp end_of_turn_label(:lithium_mode), do: "Drains enemy battery charge at end of turn"
  defp end_of_turn_label(_), do: "Activates automatically at end of turn"

  defp element_label(:fire), do: "Fire"
  defp element_label(:ice), do: "Ice"
  defp element_label(:magnetic), do: "Magnetic"
  defp element_label(:dark), do: "Dark"
  defp element_label(:water), do: "Water"
  defp element_label(_), do: ""
end
