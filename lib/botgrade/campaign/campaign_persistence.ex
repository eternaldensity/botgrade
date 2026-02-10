defmodule Botgrade.Campaign.CampaignPersistence do
  @moduledoc """
  File-based persistence for campaign state.
  Saves/loads campaign state as JSON files in priv/saves/.
  """

  alias Botgrade.Game.{CampaignState, CardSerializer}

  @saves_dir Path.join(to_string(:code.priv_dir(:botgrade)), "saves")

  def saves_dir, do: @saves_dir

  @doc "Save campaign state to a JSON file."
  @spec save(CampaignState.t()) :: :ok | {:error, term()}
  def save(%CampaignState{} = state) do
    File.mkdir_p!(@saves_dir)
    path = save_path(state.id)

    state = %{state | updated_at: DateTime.utc_now() |> DateTime.to_iso8601()}

    json =
      state
      |> CardSerializer.serialize_campaign()
      |> Jason.encode!(pretty: true)

    File.write(path, json)
  end

  @doc "Load campaign state from a JSON file."
  @spec load(String.t()) :: {:ok, CampaignState.t()} | {:error, term()}
  def load(campaign_id) do
    path = save_path(campaign_id)

    case File.read(path) do
      {:ok, json} ->
        map = Jason.decode!(json)

        case CardSerializer.deserialize_campaign(map) do
          {:ok, state} -> {:ok, state}
          {:error, reason} -> {:error, reason}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc "List saved campaign IDs with metadata."
  @spec list_saves() :: [%{id: String.t(), updated_at: String.t() | nil}]
  def list_saves do
    File.mkdir_p!(@saves_dir)

    @saves_dir
    |> File.ls!()
    |> Enum.filter(&String.ends_with?(&1, ".json"))
    |> Enum.map(fn filename ->
      id = String.trim_trailing(filename, ".json")

      case load(id) do
        {:ok, state} ->
          %{id: id, updated_at: state.updated_at, current_space_id: state.current_space_id}

        {:error, _} ->
          nil
      end
    end)
    |> Enum.reject(&is_nil/1)
    |> Enum.sort_by(& &1.updated_at, :desc)
  end

  @doc "Delete a saved campaign."
  @spec delete_save(String.t()) :: :ok | {:error, term()}
  def delete_save(campaign_id) do
    File.rm(save_path(campaign_id))
  end

  defp save_path(campaign_id) do
    Path.join(@saves_dir, "#{campaign_id}.json")
  end
end
