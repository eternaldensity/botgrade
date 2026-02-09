defmodule Botgrade.Campaign.CampaignSupervisor do
  use Supervisor

  def start_link(init_arg) do
    Supervisor.start_link(__MODULE__, init_arg, name: __MODULE__)
  end

  @impl true
  def init(_init_arg) do
    children = [
      {Registry, keys: :unique, name: Botgrade.Campaign.Registry},
      {DynamicSupervisor, name: Botgrade.Campaign.DynamicSupervisor, strategy: :one_for_one}
    ]

    Supervisor.init(children, strategy: :one_for_all)
  end

  def start_campaign(campaign_id, opts \\ []) do
    DynamicSupervisor.start_child(
      Botgrade.Campaign.DynamicSupervisor,
      {Botgrade.Campaign.CampaignServer, [campaign_id: campaign_id] ++ opts}
    )
  end
end
