defmodule BotgradeWeb.PageController do
  use BotgradeWeb, :controller

  def home(conn, _params) do
    saves = Botgrade.Campaign.CampaignPersistence.list_saves()
    render(conn, :home, saves: saves)
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

  def start_campaign(conn, _params) do
    campaign_id = Base.encode16(:crypto.strong_rand_bytes(4), case: :lower)
    {:ok, _pid} = Botgrade.Campaign.CampaignSupervisor.start_campaign(campaign_id)
    redirect(conn, to: ~p"/campaign/#{campaign_id}")
  end

  def continue_campaign(conn, %{"id" => campaign_id}) do
    {:ok, _pid} = Botgrade.Campaign.CampaignSupervisor.start_campaign(campaign_id, load_save: true)
    redirect(conn, to: ~p"/campaign/#{campaign_id}")
  end
end
