defmodule BotgradeWeb.CombatComponents do
  @moduledoc """
  Function components for the combat UI.
  """
  use Phoenix.Component
  import BotgradeWeb.CoreComponents, only: [icon: 1]

  alias Botgrade.Game.Card

  # --- Robot Status Bar ---

  attr(:robot, :map, required: true)
  attr(:label, :string, required: true)
  attr(:position, :atom, default: :top)

  def robot_status_bar(assigns) do
    hp_pct =
      if assigns.robot.total_hp > 0,
        do: assigns.robot.current_hp / assigns.robot.total_hp * 100,
        else: 0

    assigns =
      assigns
      |> assign(:hp_pct, hp_pct)
      |> assign(:hp_bar_color, hp_bar_color(assigns.robot.current_hp, assigns.robot.total_hp))

    ~H"""
    <div class={[
      "px-4 py-3 flex items-center gap-4 z-10",
      @position == :top && "sticky top-0 bg-base-100 border-b-2 border-error/30",
      @position == :bottom && "sticky bottom-0 bg-base-100 border-t-2 border-primary/30"
    ]}>
      <div class="flex items-center gap-2 shrink-0">
        <.icon :if={@position == :top} name="hero-cpu-chip" class="size-5 text-error" />
        <.icon :if={@position == :bottom} name="hero-cpu-chip" class="size-5 text-primary" />
        <div>
          <span class="font-bold text-sm">{@label}</span>
          <span class="text-xs text-base-content/60 ml-1">{@robot.name}</span>
        </div>
      </div>

      <div class="flex-1">
        <div class="flex justify-between text-xs mb-1">
          <span class="font-mono">{@robot.current_hp}/{@robot.total_hp} HP</span>
          <div class="flex items-center gap-2">
            <span :if={@robot.plating > 0} class="flex items-center gap-1 text-primary font-semibold">
              <.icon name="hero-shield-check-mini" class="size-3.5" />
              {@robot.plating} plating
            </span>
            <span :if={@robot.shield > 0} class="flex items-center gap-1 text-info font-semibold">
              <.icon name="hero-sparkles-mini" class="size-3.5" />
              {@robot.shield} shield
            </span>
          </div>
        </div>
        <div class="w-full bg-base-300 rounded-full h-3 overflow-hidden">
          <div
            class={["h-full rounded-full transition-all duration-500 ease-out", @hp_bar_color]}
            style={"width: #{@hp_pct}%"}
          />
        </div>
      </div>
    </div>
    """
  end

  # --- Phase Controls ---

  attr(:phase, :atom, required: true)
  attr(:turn_number, :integer, required: true)
  attr(:result, :atom, required: true)

  def phase_controls(assigns) do
    ~H"""
    <div :if={@result == :ongoing} class="flex items-center justify-between px-1">
      <div class="flex items-center gap-2">
        <span class="badge badge-lg badge-primary font-mono">
          Turn {@turn_number}
        </span>
        <span class="text-sm font-semibold text-base-content/80">
          {phase_label(@phase)}
        </span>
      </div>

      <div class="flex items-center gap-2">
        <span class="text-xs text-base-content/50 italic hidden sm:inline">
          {phase_hint(@phase)}
        </span>
        <button
          :if={@phase == :power_up}
          phx-click="end_turn"
          class="btn btn-sm btn-accent"
        >
          End Turn
        </button>
      </div>
    </div>
    """
  end

  # --- Dice Pool ---

  attr(:available_dice, :list, required: true)
  attr(:selected_die, :any, required: true)
  attr(:phase, :atom, required: true)

  def dice_pool(assigns) do
    ~H"""
    <div :if={length(@available_dice) > 0 or @phase == :power_up} class={[
      "card shadow-sm transition-all",
      @phase == :power_up && "bg-base-100 border-2 border-primary/30",
      @phase != :power_up && "bg-base-100"
    ]}>
      <div class="card-body p-3">
        <div class="flex items-center justify-between">
          <h3 class="card-title text-sm">
            <.icon name="hero-cube-transparent" class="size-4" />
            Dice Pool
          </h3>
          <span :if={@selected_die != nil} class="text-xs text-primary font-semibold animate-pulse">
            Tap a slot to assign
          </span>
        </div>
        <div class="flex flex-wrap gap-2 justify-center">
          <button
            :for={{die, idx} <- Enum.with_index(@available_dice)}
            phx-click="select_die"
            phx-value-die-index={idx}
            class={[
              "w-12 h-14 rounded-lg border-2 flex flex-col items-center justify-center font-mono transition-all",
              @selected_die == idx && "bg-primary text-primary-content border-primary shadow-lg shadow-primary/30 -translate-y-1 scale-105",
              @selected_die != idx && "bg-base-100 border-base-300 shadow-sm hover:shadow-md hover:-translate-y-0.5",
              @phase != :power_up && "opacity-50 cursor-not-allowed"
            ]}
            disabled={@phase != :power_up}
          >
            <span class="text-xl font-bold leading-none">{die.value}</span>
            <span class="text-[10px] opacity-60 leading-none">d{die.sides}</span>
          </button>
          <span :if={@available_dice == []} class="text-sm text-base-content/50 py-3">
            No dice available
          </span>
        </div>
      </div>
    </div>
    """
  end

  # --- Game Card ---

  attr(:card, :map, required: true)
  attr(:phase, :atom, required: true)
  attr(:selected_die, :any, required: true)
  attr(:selected_die_value, :map, default: nil)

  def game_card(assigns) do
    interactable = card_interactable?(assigns.card, assigns.phase)

    assigns = assign(assigns, :interactable, interactable)

    ~H"""
    <div class={[
      "rounded-xl border-2 p-3 text-sm flex flex-col gap-2 min-w-[160px] transition-all",
      card_bg(@card.type),
      card_border(@card.type),
      @interactable && "ring-2 ring-primary/40 shadow-lg cursor-pointer",
      not @interactable and @phase == :power_up && "opacity-60"
    ]}>
      <%!-- Header: icon + name + type badge --%>
      <div class="flex items-start justify-between gap-1">
        <div class="flex items-center gap-1.5">
          <.icon name={card_type_icon(@card.type)} class={["size-4 shrink-0", card_icon_color(@card.type)]} />
          <span class="font-bold leading-tight">{@card.name}</span>
        </div>
        <div class="flex items-center gap-1 shrink-0">
          <span :if={@card.damage == :damaged} class="badge badge-xs badge-warning">DMG</span>
          <span class={["badge badge-xs", card_badge(@card.type)]}>
            {card_type_label(@card.type)}
          </span>
        </div>
      </div>

      <%!-- Stats --%>
      <div class="text-base-content/70">
        <.card_stats card={@card} />
      </div>

      <%!-- Dice Slots --%>
      <div :if={@card.dice_slots != []} class="flex flex-wrap gap-1.5">
        <.dice_slot
          :for={slot <- @card.dice_slots}
          slot={slot}
          card={@card}
          phase={@phase}
          selected_die={@selected_die}
          selected_die_value={@selected_die_value}
        />
      </div>

      <%!-- Battery Activation Button --%>
      <button
        :if={@card.type == :battery and @phase == :power_up and @card.properties.remaining_activations > 0 and not Map.get(@card.properties, :activated_this_turn, false)}
        phx-click="activate_battery"
        phx-value-card-id={@card.id}
        class="btn btn-sm btn-primary w-full"
      >
        <.icon name="hero-bolt" class="size-4" />
        Activate
      </button>

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

      <%!-- Damage indicator strip --%>
      <div :if={@card.damage == :damaged} class="text-xs text-warning flex items-center gap-1 -mb-1">
        <.icon name="hero-exclamation-triangle-mini" class="size-3.5" />
        Damaged
      </div>
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

    <div :if={@slot.assigned_die == nil}>
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

  # --- Card Stats ---

  attr(:card, :map, required: true)

  defp card_stats(assigns) do
    ~H"""
    <%= case @card.type do %>
      <% :battery -> %>
        <div class="flex items-center gap-2">
          <%= if @card.damage == :damaged do %>
            <span class="line-through text-base-content/40 font-mono">{@card.properties.dice_count}d{@card.properties.die_sides}</span>
            <span class="text-warning font-mono">{max(@card.properties.dice_count - 1, 1)}d{@card.properties.die_sides}</span>
          <% else %>
            <span class="font-mono">{@card.properties.dice_count}d{@card.properties.die_sides}</span>
          <% end %>
          <span class="text-base-content/50">|</span>
          <.charge_dots
            remaining={@card.properties.remaining_activations}
            max={@card.properties.max_activations}
          />
        </div>
      <% :capacitor -> %>
        <span>Stores {length(@card.dice_slots)} dice</span>
      <% :weapon -> %>
        <div class="flex items-center gap-1">
          <span class="font-semibold">{String.capitalize(to_string(@card.properties.damage_type))}</span>
          <%= if @card.damage == :damaged and @card.properties.damage_base > 0 do %>
            <span class="line-through text-base-content/40 font-mono">+{@card.properties.damage_base}</span>
            <span class="text-warning font-mono">+{div(@card.properties.damage_base, 2)}</span>
          <% else %>
            <span :if={@card.properties.damage_base > 0} class="text-error font-mono">+{@card.properties.damage_base}</span>
          <% end %>
        </div>
      <% :armor -> %>
        <div class="flex items-center gap-1">
          <span class="font-semibold">{String.capitalize(to_string(@card.properties.armor_type))}</span>
          <%= if @card.damage == :damaged and @card.properties.shield_base > 0 do %>
            <span class="line-through text-base-content/40 font-mono">+{@card.properties.shield_base}</span>
            <span class="text-warning font-mono">+{div(@card.properties.shield_base, 2)}</span>
          <% else %>
            <span :if={@card.properties.shield_base > 0} class="text-info font-mono">+{@card.properties.shield_base}</span>
          <% end %>
        </div>
      <% :locomotion -> %>
        <span>Speed <span class="font-mono text-success">+{@card.properties.speed_base}</span></span>
      <% :chassis -> %>
        <div class="flex items-center gap-1">
          <.icon name="hero-heart-mini" class="size-3.5 text-error" />
          <%= if @card.damage == :damaged do %>
            <span class="line-through text-base-content/40 font-mono">{@card.properties.hp_max} HP</span>
            <span class="text-warning font-mono">{div(@card.properties.hp_max, 2)} HP</span>
          <% else %>
            <span class="font-mono">{@card.properties.hp_max} HP</span>
          <% end %>
        </div>
    <% end %>
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

  # --- Card Area (hand / in-play) ---

  attr(:title, :string, required: true)
  attr(:cards, :list, required: true)
  attr(:phase, :atom, required: true)
  attr(:selected_die, :any, required: true)
  attr(:selected_die_value, :map, default: nil)
  attr(:count, :integer, default: nil)
  attr(:scrollable, :boolean, default: false)

  def card_area(assigns) do
    assigns =
      assign_new(assigns, :display_count, fn -> assigns.count || length(assigns.cards) end)

    ~H"""
    <div class="card bg-base-100 shadow-sm">
      <div class="card-body p-3">
        <h3 class="card-title text-sm">
          {@title}
          <span class="badge badge-sm badge-ghost">{@display_count}</span>
        </h3>
        <div class={[
          @scrollable && "flex overflow-x-auto gap-3 pb-2 snap-x md:grid md:grid-cols-3 lg:grid-cols-5 md:overflow-visible",
          not @scrollable && "grid grid-cols-2 md:grid-cols-3 lg:grid-cols-4 gap-3"
        ]}>
          <div :for={card <- @cards} class={[@scrollable && "snap-start shrink-0"]}>
            <.game_card
              card={card}
              phase={@phase}
              selected_die={@selected_die}
              selected_die_value={@selected_die_value}
            />
          </div>
        </div>
      </div>
    </div>
    """
  end

  # --- Scavenge Panel ---

  attr(:state, :map, required: true)

  def scavenge_panel(assigns) do
    ~H"""
    <div class="card bg-base-100 shadow-lg">
      <div class="card-body">
        <h2 class="text-2xl font-bold text-success text-center mb-2">VICTORY!</h2>
        <h3 class="card-title text-lg">
          <.icon name="hero-wrench-screwdriver" class="size-5" />
          Scavenge Enemy Wreckage
          <span class="badge badge-sm">
            {length(@state.scavenge_selected)}/{@state.scavenge_limit} selected
          </span>
        </h3>

        <div class="grid grid-cols-2 md:grid-cols-3 lg:grid-cols-4 gap-3 mt-2">
          <div
            :for={card <- @state.scavenge_loot}
            phx-click="toggle_scavenge_card"
            phx-value-card-id={card.id}
            class={[
              "rounded-xl border-2 p-3 text-sm cursor-pointer transition-all hover:ring-2 ring-primary",
              card_bg(card.type),
              card_border(card.type),
              card.id in @state.scavenge_selected && "ring-2 ring-success bg-success/10"
            ]}
          >
            <div class="flex justify-between items-start mb-1">
              <div class="flex items-center gap-1.5">
                <.icon name={card_type_icon(card.type)} class={["size-4", card_icon_color(card.type)]} />
                <span class="font-bold">{card.name}</span>
              </div>
              <span class={["badge badge-xs", card_badge(card.type)]}>
                {card_type_label(card.type)}
              </span>
            </div>
            <div class="text-base-content/60 mb-1">
              <.card_stats card={card} />
            </div>
            <div class="flex gap-1 mt-1">
              <span :if={card.damage == :damaged} class="badge badge-xs badge-warning">DAMAGED</span>
              <span :if={card.damage == :intact} class="badge badge-xs badge-success">INTACT</span>
              <span :if={card.id in @state.scavenge_selected} class="badge badge-xs badge-accent">SELECTED</span>
            </div>
          </div>
        </div>

        <div :if={@state.scavenge_loot == []} class="text-center text-base-content/50 py-4">
          Nothing salvageable remains.
        </div>

        <div class="card-actions justify-center mt-4 gap-2">
          <button phx-click="confirm_scavenge" class="btn btn-primary">
            Take {length(@state.scavenge_selected)} Card{if length(@state.scavenge_selected) != 1, do: "s", else: ""}
          </button>
          <button phx-click="confirm_scavenge" class="btn btn-ghost">
            Skip
          </button>
        </div>
      </div>
    </div>
    """
  end

  # --- End Screen ---

  attr(:result, :atom, required: true)

  def end_screen(assigns) do
    ~H"""
    <div class="card bg-base-100 shadow-lg" style="animation: result-entrance 0.4s ease-out">
      <div class="card-body text-center py-8">
        <h2 class={[
          "text-3xl font-bold",
          @result == :player_wins && "text-success",
          @result == :enemy_wins && "text-error"
        ]}>
          {if @result == :player_wins, do: "VICTORY!", else: "DEFEAT"}
        </h2>
        <p class="text-base-content/60 text-sm mt-1">
          {if @result == :player_wins, do: "Enemy robot destroyed.", else: "Your robot has been destroyed."}
        </p>
        <div class="card-actions justify-center mt-4 gap-2">
          <button :if={@result == :player_wins} phx-click="next_combat" class="btn btn-primary">
            <.icon name="hero-arrow-right" class="size-4" />
            Next Combat
          </button>
          <button phx-click="new_combat" class="btn btn-outline">
            <.icon name="hero-arrow-path" class="size-4" />
            New Game
          </button>
        </div>
      </div>
    </div>
    """
  end

  # --- Combat Log ---

  attr(:log, :list, required: true)

  def combat_log(assigns) do
    ~H"""
    <div class="card bg-base-100 shadow-sm">
      <div class="card-body p-3">
        <h3 class="card-title text-xs text-base-content/60">
          <.icon name="hero-document-text-mini" class="size-3.5" />
          Combat Log
        </h3>
        <div class="h-20 overflow-y-auto text-xs font-mono space-y-0.5">
          <div :for={msg <- @log} class="text-base-content/60">
            {msg}
          </div>
        </div>
      </div>
    </div>
    """
  end

  # --- Helper Functions ---

  defp phase_label(:draw), do: "Draw"
  defp phase_label(:power_up), do: "Power Up"
  defp phase_label(:enemy_turn), do: "Enemy Turn"
  defp phase_label(:scavenging), do: "Scavenging"
  defp phase_label(:ended), do: "Combat Over"

  defp phase_hint(:power_up), do: "Activate batteries, then assign dice to cards"
  defp phase_hint(_), do: ""

  defp card_type_icon(:battery), do: "hero-bolt"
  defp card_type_icon(:capacitor), do: "hero-circle-stack"
  defp card_type_icon(:weapon), do: "hero-fire"
  defp card_type_icon(:armor), do: "hero-shield-check"
  defp card_type_icon(:locomotion), do: "hero-arrow-trending-up"
  defp card_type_icon(:chassis), do: "hero-cube"

  defp card_icon_color(:battery), do: "text-warning"
  defp card_icon_color(:capacitor), do: "text-info"
  defp card_icon_color(:weapon), do: "text-error"
  defp card_icon_color(:armor), do: "text-primary"
  defp card_icon_color(:locomotion), do: "text-success"
  defp card_icon_color(:chassis), do: "text-base-content/50"

  defp card_bg(:battery), do: "bg-gradient-to-b from-warning/10 to-transparent"
  defp card_bg(:capacitor), do: "bg-gradient-to-b from-info/10 to-transparent"
  defp card_bg(:weapon), do: "bg-gradient-to-b from-error/10 to-transparent"
  defp card_bg(:armor), do: "bg-gradient-to-b from-primary/10 to-transparent"
  defp card_bg(:locomotion), do: "bg-gradient-to-b from-success/10 to-transparent"
  defp card_bg(:chassis), do: "bg-gradient-to-b from-base-300/20 to-transparent"

  defp card_border(:battery), do: "border-warning/50"
  defp card_border(:capacitor), do: "border-info/50"
  defp card_border(:weapon), do: "border-error/50"
  defp card_border(:armor), do: "border-primary/50"
  defp card_border(:locomotion), do: "border-success/50"
  defp card_border(:chassis), do: "border-base-300"

  defp card_badge(:battery), do: "badge-warning"
  defp card_badge(:capacitor), do: "badge-info"
  defp card_badge(:weapon), do: "badge-error"
  defp card_badge(:armor), do: "badge-primary"
  defp card_badge(:locomotion), do: "badge-success"
  defp card_badge(:chassis), do: "badge-ghost"

  defp card_type_label(:battery), do: "Battery"
  defp card_type_label(:capacitor), do: "Capacitor"
  defp card_type_label(:weapon), do: "Weapon"
  defp card_type_label(:armor), do: "Armor"
  defp card_type_label(:locomotion), do: "Movement"
  defp card_type_label(:chassis), do: "Chassis"

  defp condition_label({:min, n}), do: "#{n}+"
  defp condition_label({:max, n}), do: "#{n}-"
  defp condition_label({:exact, n}), do: "=#{n}"
  defp condition_label(:even), do: "even"
  defp condition_label(:odd), do: "odd"
  defp condition_label(nil), do: ""

  defp result_label(%{type: :damage, value: v}), do: "#{v} dmg"
  defp result_label(%{type: :plating, value: v}), do: "+#{v} plating"
  defp result_label(%{type: :shield, value: v}), do: "+#{v} shield"

  defp hp_bar_color(current, total) when current > total * 0.5, do: "bg-success"
  defp hp_bar_color(current, total) when current > total * 0.25, do: "bg-warning"
  defp hp_bar_color(_current, _total), do: "bg-error"

  defp card_interactable?(card, :power_up) do
    cond do
      card.type == :battery and
        card.properties.remaining_activations > 0 and
          not Map.get(card.properties, :activated_this_turn, false) ->
        true

      card.dice_slots != [] and Enum.any?(card.dice_slots, &(&1.assigned_die == nil)) ->
        true

      true ->
        false
    end
  end

  defp card_interactable?(_card, _phase), do: false
end
