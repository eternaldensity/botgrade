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
      <%!-- Header: icon + name + type badge --%>
      <%!-- Single tag: show inline with title. Multiple tags: separate line. --%>
      <div class={["flex items-start gap-1", @card.damage != :damaged && "justify-between"]}>
        <div class="flex items-center gap-1.5">
          <.icon name={card_type_icon(@card.type)} class={["size-4 shrink-0", card_icon_color(@card.type)]} />
          <span class="font-bold leading-tight">{@card.name}</span>
          <%!-- Single badge inline when not damaged --%>
          <span :if={@destroyed and @card.damage != :damaged} class="badge badge-xs badge-error shrink-0">DEAD</span>
          <span :if={not @destroyed and @card.damage != :damaged} class={["badge badge-xs shrink-0", card_badge(@card.type)]}>
            {card_type_label(@card.type)}
          </span>
        </div>
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
        Boost +1
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
            Activate: stored die +1 (1x/turn)
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
        <div class="flex items-center gap-1">
          <.icon name="hero-heart-mini" class="size-3.5 text-error" />
          <span class="font-mono">{Map.get(@card.properties, :card_hp, 0)} HP</span>
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
  defp utility_ability_label(_), do: "Utility"

  defp utility_ability_description(:beam_split), do: "Split a die into two halves"
  defp utility_ability_description(:overcharge), do: "Weapons deal +1 damage this turn"
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

  defp element_label(:fire), do: "Fire"
  defp element_label(:ice), do: "Ice"
  defp element_label(:magnetic), do: "Magnetic"
  defp element_label(:dark), do: "Dark"
  defp element_label(:water), do: "Water"
  defp element_label(_), do: ""
end
