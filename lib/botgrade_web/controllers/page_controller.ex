defmodule BotgradeWeb.PageController do
  use BotgradeWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end

  def start_combat(conn, params) do
    combat_id = Base.encode16(:crypto.strong_rand_bytes(4), case: :lower)
    enemy_type = params["enemy_type"]

    opts =
      case enemy_type do
        nil -> []
        "rogue" -> []
        type -> [enemy_cards: Botgrade.Game.StarterDecks.enemy_deck(type)]
      end

    {:ok, _pid} = Botgrade.Combat.CombatSupervisor.start_combat(combat_id, opts)
    redirect(conn, to: ~p"/combat/#{combat_id}")
  end
end
