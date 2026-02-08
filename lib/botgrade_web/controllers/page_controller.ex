defmodule BotgradeWeb.PageController do
  use BotgradeWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end

  def start_combat(conn, _params) do
    combat_id = Base.encode16(:crypto.strong_rand_bytes(4), case: :lower)
    {:ok, _pid} = Botgrade.Combat.CombatSupervisor.start_combat(combat_id)
    redirect(conn, to: ~p"/combat/#{combat_id}")
  end
end
