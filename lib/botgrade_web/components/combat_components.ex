defmodule BotgradeWeb.CombatComponents do
  @moduledoc """
  Function components for the combat UI layout.

  Handles the overall combat screen: status bars, dice pool, board areas,
  scavenge panel, end screen, and combat log. Individual card rendering
  lives in `BotgradeWeb.CombatCardComponents`.
  """
  use Phoenix.Component
  import BotgradeWeb.CoreComponents, only: [icon: 1]

  import BotgradeWeb.CombatCardComponents,
    only: [
      game_card: 1,
      card_detail_stats: 1,
      card_type_icon: 1,
      card_icon_color: 1,
      card_bg: 1,
      card_border: 1,
      card_badge: 1,
      card_type_label: 1,
      hp_bar_color: 2
    ]

  alias Botgrade.Game.Robot

  # --- Robot Status Bar ---

  attr(:robot, :map, required: true)
  attr(:label, :string, required: true)
  attr(:position, :atom, default: :top)
  attr(:combat_number, :integer, default: nil)

  def robot_status_bar(assigns) do
    total_hp = Robot.total_hp(assigns.robot)
    current_hp = Robot.current_hp(assigns.robot)

    hp_pct =
      if total_hp > 0,
        do: current_hp / total_hp * 100,
        else: 0

    assigns =
      assigns
      |> assign(:total_hp, total_hp)
      |> assign(:current_hp, current_hp)
      |> assign(:hp_pct, hp_pct)
      |> assign(:hp_bar_color, hp_bar_color(current_hp, total_hp))

    ~H"""
    <div class={[
      "px-4 py-3 flex items-center gap-4 z-10",
      @position == :top && "sticky top-0 bg-base-100 border-b-2 border-error/30",
      @position == :bottom && "sticky bottom-0 bg-base-100 border-t-2 border-primary/30"
    ]}>
      <.link :if={@combat_number} navigate="/" class="btn btn-ghost btn-xs gap-1 text-base-content/60 hover:text-base-content shrink-0">
        <.icon name="hero-arrow-left-mini" class="size-3.5" />
        Menu
      </.link>
      <span :if={@combat_number} class="badge badge-sm badge-neutral shrink-0">Fight {@combat_number}</span>
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
          <span class="font-mono">{@current_hp}/{@total_hp} HP</span>
          <div class="flex items-center gap-2">
            <span :if={@robot.plating > 0} class="flex items-center gap-1 text-primary font-semibold">
              <.icon name="hero-shield-check-mini" class="size-3.5" />
              {@robot.plating} plating
            </span>
            <span :if={@robot.shield > 0} class="flex items-center gap-1 text-info font-semibold">
              <.icon name="hero-sparkles-mini" class="size-3.5" />
              {@robot.shield} shield
            </span>
            <span
              :for={{type, count} <- Enum.sort_by(@robot.resources, fn {k, _} -> Atom.to_string(k) end)}
              :if={@position == :bottom and count > 0}
              class="flex items-center gap-0.5 text-warning/80 font-semibold"
            >
              <span class="text-[10px]">{scrap_label(type)}</span>
              <span class="font-mono">{count}</span>
            </span>
            <span
              :for={{effect, stacks} <- Enum.sort_by(Map.to_list(@robot.status_effects || %{}), fn {k, _} -> Atom.to_string(k) end)}
              :if={stacks > 0}
              class={["flex items-center gap-0.5 font-semibold", status_effect_color(effect)]}
            >
              <span class="text-[10px]">{status_effect_label(effect)}</span>
              <span class="font-mono">{stacks}</span>
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
  attr(:target_lock_active, :boolean, default: false)
  attr(:overclock_active, :boolean, default: false)
  attr(:overcharge_bonus, :integer, default: 0)

  def phase_controls(assigns) do
    ~H"""
    <div :if={@result == :ongoing} class="flex items-center justify-between px-1">
      <div class="flex items-center gap-2">
        <span class="text-sm font-mono font-semibold text-base-content/60">
          Turn {@turn_number}
        </span>
        <span :if={@target_lock_active} class="badge badge-sm badge-warning animate-pulse">
          TARGET LOCK
        </span>
        <span :if={@overclock_active} class="badge badge-sm badge-warning animate-pulse">
          OVERCLOCK
        </span>
        <span :if={@overcharge_bonus > 0} class="badge badge-sm badge-error animate-pulse">
          OVERCHARGE +{@overcharge_bonus}
        </span>
        <span :if={@phase == :enemy_turn} class="badge badge-sm badge-error animate-pulse">
          Enemy attacking...
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
              @selected_die != idx && Map.get(die, :blazing) && "bg-orange-500/20 border-orange-500 shadow-sm hover:shadow-md hover:-translate-y-0.5",
              @selected_die != idx && not Map.get(die, :blazing, false) && "bg-base-100 border-base-300 shadow-sm hover:shadow-md hover:-translate-y-0.5",
              @phase != :power_up && "opacity-50 cursor-not-allowed"
            ]}
            disabled={@phase != :power_up}
          >
            <span class="text-xl font-bold leading-none">
              {if Map.get(die, :hidden), do: "?", else: die.value}
            </span>
            <span class="text-[10px] opacity-60 leading-none">d{die.sides}</span>
            <span :if={Map.get(die, :blazing)} class="text-[8px] text-orange-500 font-bold leading-none">BLAZE</span>
          </button>
          <span :if={@available_dice == []} class="text-sm text-base-content/50 py-3">
            No dice available
          </span>
        </div>
      </div>
    </div>
    """
  end

  # --- Enemy Board ---

  attr(:robot, :map, required: true)
  attr(:last_attack_result, :map, default: nil)

  def enemy_board(assigns) do
    cards = assigns.robot.installed ++ assigns.robot.hand
    assigns = assign(assigns, :cards, cards)

    ~H"""
    <div class="card bg-base-100 shadow-sm border border-error/20">
      <div class="card-body p-3">
        <h3 class="card-title text-sm text-error">
          <.icon name="hero-cpu-chip" class="size-4" />
          Enemy Components
          <span class="badge badge-sm badge-ghost">{length(@cards)}</span>
        </h3>
        <div class="grid grid-cols-3 md:grid-cols-4 lg:grid-cols-6 gap-2">
          <.enemy_card
            :for={card <- @cards}
            card={card}
            hit={@last_attack_result != nil and @last_attack_result.target == card.id}
          />
        </div>
      </div>
    </div>
    """
  end

  # --- Enemy Card (compact) ---

  attr(:card, :map, required: true)
  attr(:hit, :boolean, default: false)

  defp enemy_card(assigns) do
    max_hp = Map.get(assigns.card.properties, :card_hp, 2)
    current_hp = assigns.card.current_hp || 0
    hp_pct = if max_hp > 0, do: current_hp / max_hp * 100, else: 0
    destroyed = current_hp <= 0

    assigns =
      assigns
      |> assign(:max_hp, max_hp)
      |> assign(:hp_pct, hp_pct)
      |> assign(:destroyed, destroyed)

    ~H"""
    <div class={[
      "rounded-lg border p-2 text-xs transition-all",
      card_border(@card.type),
      @destroyed && "opacity-25 grayscale",
      not @destroyed && card_bg(@card.type),
      @hit && "ring-2 ring-error animate-pulse"
    ]}>
      <div class="flex items-center gap-1 mb-1">
        <.icon name={card_type_icon(@card.type)} class={["size-3 shrink-0", card_icon_color(@card.type)]} />
        <span class="font-bold truncate">{@card.name}</span>
      </div>
      <div :if={not @destroyed} class="w-full bg-base-300 rounded-full h-1.5 mb-1 overflow-hidden">
        <div
          class={["h-full rounded-full transition-all", hp_bar_color(@card.current_hp, @max_hp)]}
          style={"width: #{@hp_pct}%"}
        />
      </div>
      <span :if={not @destroyed} class="font-mono text-[10px]">{@card.current_hp}/{@max_hp}</span>
      <span :if={@destroyed} class="font-mono text-[10px] text-error">DESTROYED</span>
    </div>
    """
  end

  # --- Installed Components (player) ---

  attr(:cards, :list, required: true)
  attr(:last_attack_result, :map, default: nil)
  attr(:phase, :atom, default: nil)
  attr(:cpu_targeting, :string, default: nil)
  attr(:cpu_discard_selected, :list, default: [])
  attr(:cpu_targeting_mode, :atom, default: nil)

  def installed_components(assigns) do
    ~H"""
    <div :if={@cards != []} class="card bg-base-100 shadow-sm border border-primary/20">
      <div class="card-body p-3">
        <h3 class="card-title text-sm text-primary">
          <.icon name="hero-wrench-screwdriver" class="size-4" />
          Your Components
          <span class="badge badge-sm badge-ghost">{length(@cards)}</span>
        </h3>
        <div class="grid grid-cols-3 md:grid-cols-4 lg:grid-cols-6 gap-2">
          <.installed_card
            :for={card <- @cards}
            card={card}
            hit={@last_attack_result != nil and @last_attack_result.target == card.id}
            phase={@phase}
            cpu_targeting={@cpu_targeting}
            cpu_discard_selected={@cpu_discard_selected}
            cpu_targeting_mode={@cpu_targeting_mode}
          />
        </div>
      </div>
    </div>
    """
  end

  # --- Installed Card (compact, for player's chassis/cpu/locomotion) ---

  attr(:card, :map, required: true)
  attr(:hit, :boolean, default: false)
  attr(:phase, :atom, default: nil)
  attr(:cpu_targeting, :string, default: nil)
  attr(:cpu_discard_selected, :list, default: [])
  attr(:cpu_targeting_mode, :atom, default: nil)

  defp installed_card(assigns) do
    max_hp = Map.get(assigns.card.properties, :card_hp, 2)
    current_hp = assigns.card.current_hp || 0
    hp_pct = if max_hp > 0, do: current_hp / max_hp * 100, else: 0
    destroyed = current_hp <= 0

    assigns =
      assigns
      |> assign(:max_hp, max_hp)
      |> assign(:hp_pct, hp_pct)
      |> assign(:destroyed, destroyed)

    ~H"""
    <div class={[
      "rounded-lg border p-2 text-xs transition-all",
      card_border(@card.type),
      @destroyed && "opacity-25 grayscale",
      not @destroyed && card_bg(@card.type),
      @hit && "ring-2 ring-error animate-pulse",
      @cpu_targeting == @card.id && "ring-2 ring-secondary"
    ]}>
      <div class="flex items-center gap-1 mb-1">
        <.icon name={card_type_icon(@card.type)} class={["size-3 shrink-0", card_icon_color(@card.type)]} />
        <span class="font-bold truncate">{@card.name}</span>
      </div>
      <div :if={not @destroyed} class="w-full bg-base-300 rounded-full h-1.5 mb-1 overflow-hidden">
        <div
          class={["h-full rounded-full transition-all", hp_bar_color(@card.current_hp, @max_hp)]}
          style={"width: #{@hp_pct}%"}
        />
      </div>
      <span :if={not @destroyed} class="font-mono text-[10px]">{@card.current_hp}/{@max_hp}</span>
      <span :if={@destroyed} class="font-mono text-[10px] text-error">DESTROYED</span>

      <%!-- CPU Ability: Activate button --%>
      <button
        :if={
          @card.type == :cpu and
          @phase == :power_up and
          not @destroyed and
          is_nil(@cpu_targeting) and
          not Map.get(@card.properties, :activated_this_turn, false) and
          Map.has_key?(@card.properties, :cpu_ability)
        }
        phx-click="activate_cpu"
        phx-value-card-id={@card.id}
        class="btn btn-xs btn-secondary w-full mt-1"
      >
        Activate
      </button>

      <%!-- CPU Ability: Already activated indicator --%>
      <span
        :if={
          @card.type == :cpu and
          not @destroyed and
          Map.get(@card.properties, :activated_this_turn, false)
        }
        class="text-[10px] text-secondary/50 mt-1"
      >
        Used this turn
      </span>

      <%!-- CPU Targeting Mode: ability-specific UI --%>
      <div :if={@cpu_targeting == @card.id and not @destroyed} class="mt-1 space-y-1">
        <%= case @cpu_targeting_mode do %>
          <% :select_hand_cards -> %>
            <span class="text-[10px] text-secondary font-semibold">
              Discard {@card.properties.cpu_ability.discard_count} card(s)
              ({length(@cpu_discard_selected)} selected)
            </span>
            <div class="flex gap-1">
              <button
                :if={length(@cpu_discard_selected) == @card.properties.cpu_ability.discard_count}
                phx-click="confirm_cpu_ability"
                class="btn btn-xs btn-success flex-1"
              >
                Confirm
              </button>
              <button phx-click="cancel_cpu_ability" class="btn btn-xs btn-ghost flex-1">Cancel</button>
            </div>
          <% :select_installed_card -> %>
            <span class="text-[10px] text-secondary font-semibold">
              {cpu_targeting_label(@card.properties.cpu_ability)}
            </span>
            <div class="flex gap-1">
              <button phx-click="confirm_cpu_ability" class="btn btn-xs btn-success flex-1">Confirm</button>
              <button phx-click="cancel_cpu_ability" class="btn btn-xs btn-ghost flex-1">Cancel</button>
            </div>
          <% _ -> %>
        <% end %>
      </div>
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
  attr(:cpu_targeting, :string, default: nil)
  attr(:cpu_discard_selected, :list, default: [])
  attr(:cpu_targeting_mode, :atom, default: nil)
  attr(:cpu_selected_installed, :string, default: nil)
  attr(:cpu_ability_type, :atom, default: nil)

  def card_area(assigns) do
    assigns =
      assign_new(assigns, :display_count, fn -> assigns.count || length(assigns.cards) end)

    ~H"""
    <div class="card bg-base-100 shadow-sm">
      <div class="card-body p-3">
        <h3 class="card-title text-sm">
          {@title}
          <span class="badge badge-sm badge-ghost">{@display_count}</span>
          <span :if={@cpu_targeting} class="badge badge-sm badge-secondary">{cpu_targeting_instruction(@cpu_targeting_mode)}</span>
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
              cpu_targeting={@cpu_targeting}
              cpu_discard_selected={@cpu_discard_selected}
              cpu_targeting_mode={@cpu_targeting_mode}
              cpu_selected_installed={@cpu_selected_installed}
              cpu_ability_type={@cpu_ability_type}
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

        <div :if={map_size(@state.scavenge_scraps) > 0} class="bg-warning/10 border border-warning/30 rounded-xl p-3 mt-2">
          <h4 class="text-sm font-bold flex items-center gap-1.5 mb-2">
            <.icon name="hero-cog-6-tooth" class="size-4 text-warning" />
            Scrap Recovered
            <span class="text-xs font-normal text-base-content/60">(auto-collected)</span>
          </h4>
          <div class="flex flex-wrap gap-2">
            <div
              :for={{type, count} <- Enum.sort_by(@state.scavenge_scraps, fn {k, _} -> Atom.to_string(k) end)}
              class="flex items-center gap-1.5 bg-base-100 rounded-lg px-2.5 py-1.5 border border-base-300"
            >
              <.icon name={scrap_icon(type)} class={["size-4", scrap_color(type)]} />
              <span class="font-semibold text-sm">{scrap_label(type)}</span>
              <span class="badge badge-sm badge-warning font-mono">x{count}</span>
            </div>
          </div>
        </div>

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
              <.card_detail_stats card={card} />
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
  attr(:campaign_id, :string, default: nil)

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
          <%!-- Campaign victory: Return to Map --%>
          <button :if={not is_nil(@campaign_id) and @result == :player_wins} phx-click="return_to_map" class="btn btn-primary">
            <.icon name="hero-map" class="size-4" />
            Return to Map
          </button>
          <%!-- Campaign defeat: Campaign Over --%>
          <button :if={not is_nil(@campaign_id) and @result == :enemy_wins} phx-click="campaign_over" class="btn btn-error">
            <.icon name="hero-x-mark" class="size-4" />
            Campaign Over
          </button>
          <%!-- Standalone mode: Next Combat / New Game --%>
          <button :if={@result == :player_wins and is_nil(@campaign_id)} phx-click="next_combat" class="btn btn-primary">
            <.icon name="hero-arrow-right" class="size-4" />
            Next Combat
          </button>
          <button :if={is_nil(@campaign_id)} phx-click="new_combat" class="btn btn-outline">
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

  defp phase_hint(:power_up), do: "Activate batteries, then assign dice to cards"
  defp phase_hint(_), do: ""

  defp cpu_targeting_instruction(:select_hand_cards), do: "Select cards to discard"
  defp cpu_targeting_instruction(:select_installed_card), do: "Select a card to target"
  defp cpu_targeting_instruction(_), do: ""

  defp cpu_targeting_label(%{type: :reflex_block}), do: "Select armor to boost (+1 shield)"
  defp cpu_targeting_label(%{type: :siphon_power}), do: "Select battery to restore (costs 2 shield)"
  defp cpu_targeting_label(%{type: :extra_activation}), do: "Select a used card to reactivate"
  defp cpu_targeting_label(_), do: "Select a target"

  # --- Scrap Helpers ---

  defp scrap_icon(:metal), do: "hero-cube-transparent"
  defp scrap_icon(:wire), do: "hero-link"
  defp scrap_icon(:plastic), do: "hero-square-3-stack-3d"
  defp scrap_icon(:grease), do: "hero-beaker"
  defp scrap_icon(:chips), do: "hero-cpu-chip"

  defp scrap_color(:metal), do: "text-base-content/70"
  defp scrap_color(:wire), do: "text-amber-500"
  defp scrap_color(:plastic), do: "text-blue-400"
  defp scrap_color(:grease), do: "text-yellow-600"
  defp scrap_color(:chips), do: "text-emerald-500"

  defp scrap_label(:metal), do: "Metal"
  defp scrap_label(:wire), do: "Wire"
  defp scrap_label(:plastic), do: "Plastic"
  defp scrap_label(:grease), do: "Grease"
  defp scrap_label(:chips), do: "Chips"

  defp status_effect_color(:overheated), do: "text-orange-500"
  defp status_effect_color(:subzero), do: "text-cyan-400"
  defp status_effect_color(:fused), do: "text-violet-500"
  defp status_effect_color(:hidden), do: "text-gray-400"
  defp status_effect_color(:rust), do: "text-amber-700"
  defp status_effect_color(_), do: "text-base-content/60"

  defp status_effect_label(:overheated), do: "OVERHEAT"
  defp status_effect_label(:subzero), do: "SUBZERO"
  defp status_effect_label(:fused), do: "FUSED"
  defp status_effect_label(:hidden), do: "HIDDEN"
  defp status_effect_label(:rust), do: "RUST"
  defp status_effect_label(other), do: other |> Atom.to_string() |> String.upcase()
end
