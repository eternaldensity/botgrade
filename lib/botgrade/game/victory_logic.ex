defmodule Botgrade.Game.VictoryLogic do
  @moduledoc """
  Handles victory and defeat condition checking for combat.

  This module determines when a combatant (player or enemy) has been defeated
  based on various conditions like destroyed chassis, CPU failure, power exhaustion, etc.
  """

  alias Botgrade.Game.{CombatState, Robot, ScavengeLogic}

  @doc """
  Checks if either combatant has been defeated and updates the combat state accordingly.

  If the enemy is defeated, transitions to scavenge phase.
  If the player is defeated, ends the combat.

  Returns the updated combat state with result set to :player_wins, :enemy_wins, or :ongoing.
  """
  @spec check_victory(CombatState.t()) :: CombatState.t()
  def check_victory(state) do
    case {check_defeat(state.enemy), check_defeat(state.player)} do
      {{:defeated, reason}, _} ->
        %{state | result: :player_wins}
        |> add_log("Enemy defeated: #{defeat_message(reason)}")
        |> ScavengeLogic.begin_scavenge()

      {_, {:defeated, reason}} ->
        %{state | result: :enemy_wins, phase: :ended}
        |> add_log("You have been defeated: #{defeat_message(reason)}")

      _ ->
        state
    end
  end

  @doc """
  Checks if a robot has been defeated based on various conditions.

  Returns :alive if the robot can continue fighting, or {:defeated, reason} if defeated.

  Defeat conditions:
  - All chassis destroyed
  - All CPU destroyed (if robot has CPU cards)
  - All weapons AND locomotion destroyed
  - All power generation destroyed/depleted
  """
  @spec check_defeat(Robot.t()) :: :alive | {:defeated, atom()}
  def check_defeat(robot) do
    all_cards = robot.installed ++ robot.deck ++ robot.hand ++ robot.discard

    installed_alive =
      robot.installed
      |> Enum.filter(&(&1.current_hp != nil and &1.current_hp > 0))
      |> Enum.group_by(& &1.type)

    all_alive =
      all_cards
      |> Enum.filter(&(&1.current_hp != nil and &1.current_hp > 0))
      |> Enum.group_by(& &1.type)

    cond do
      # All chassis destroyed
      not Map.has_key?(installed_alive, :chassis) ->
        {:defeated, :chassis_destroyed}

      # All CPU destroyed (only if bot has CPU cards)
      has_type?(robot.installed, :cpu) and not Map.has_key?(installed_alive, :cpu) ->
        {:defeated, :cpu_destroyed}

      # All weapons AND locomotion destroyed
      not Map.has_key?(all_alive, :weapon) and not Map.has_key?(installed_alive, :locomotion) ->
        {:defeated, :disarmed_and_immobile}

      # All power generation destroyed/depleted
      power_exhausted?(all_cards) ->
        {:defeated, :power_failure}

      true ->
        :alive
    end
  end

  @doc """
  Returns a human-readable defeat message for the given defeat reason.
  """
  @spec defeat_message(atom()) :: String.t()
  def defeat_message(:chassis_destroyed),
    do: "Structural failure! All chassis components destroyed."

  def defeat_message(:cpu_destroyed), do: "System crash! All CPU modules destroyed."

  def defeat_message(:disarmed_and_immobile),
    do: "Neutralized! All weapons and locomotion destroyed."

  def defeat_message(:power_failure),
    do: "Power failure! All energy sources depleted or destroyed."

  # --- Private Helpers ---

  defp has_type?(cards, type), do: Enum.any?(cards, &(&1.type == type))

  defp power_exhausted?(all_cards) do
    batteries = Enum.filter(all_cards, &(&1.type == :battery))
    capacitors = Enum.filter(all_cards, &(&1.type == :capacitor))

    if batteries == [] and capacitors == [] do
      false
    else
      batteries_dead =
        Enum.all?(batteries, fn bat ->
          (bat.current_hp != nil and bat.current_hp <= 0) or
            Map.get(bat.properties, :remaining_activations, 0) <= 0
        end)

      capacitors_dead =
        Enum.all?(capacitors, fn cap ->
          cap.current_hp != nil and cap.current_hp <= 0
        end)

      batteries_dead and capacitors_dead
    end
  end

  defp add_log(state, message) do
    %{state | log: [message | state.log]}
  end
end
