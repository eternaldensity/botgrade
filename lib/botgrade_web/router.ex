defmodule BotgradeWeb.Router do
  use BotgradeWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {BotgradeWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/", BotgradeWeb do
    pipe_through :browser

    get "/", PageController, :home
    post "/combat/start", PageController, :start_combat
    post "/campaign/start", PageController, :start_campaign
    get "/campaign/continue/:id", PageController, :continue_campaign
    post "/campaign/delete/:id", PageController, :delete_campaign
    live "/campaign/:id", CampaignLive
    live "/combat/:id", CombatLive
  end

  # Other scopes may use custom stacks.
  # scope "/api", BotgradeWeb do
  #   pipe_through :api
  # end
end
