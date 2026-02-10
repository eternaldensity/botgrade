defmodule Botgrade.Campaign.CampaignServer do
  use GenServer

  alias Botgrade.Game.{CampaignState, MapGenerator, ScrapLogic, StarterDecks, UpgradeLogic}
  alias Botgrade.Campaign.CampaignPersistence
  alias Botgrade.Combat.CombatSupervisor

  @idle_timeout :timer.minutes(30)

  # --- Client API ---

  def start_link(opts) do
    campaign_id = Keyword.fetch!(opts, :campaign_id)
    GenServer.start_link(__MODULE__, opts, name: via(campaign_id))
  end

  def get_state(campaign_id), do: GenServer.call(via(campaign_id), :get_state)

  def move_to_space(campaign_id, space_id),
    do: GenServer.call(via(campaign_id), {:move_to_space, space_id})

  def end_turn(campaign_id),
    do: GenServer.call(via(campaign_id), :end_turn)

  def complete_combat(campaign_id, player_cards, player_resources, result),
    do: GenServer.call(via(campaign_id), {:complete_combat, player_cards, player_resources, result})

  def save(campaign_id), do: GenServer.call(via(campaign_id), :save)

  def rest_repair(campaign_id, card_id),
    do: GenServer.call(via(campaign_id), {:rest_repair, card_id})

  def shop_buy(campaign_id, card_index),
    do: GenServer.call(via(campaign_id), {:shop_buy, card_index})

  def clear_current_space(campaign_id),
    do: GenServer.call(via(campaign_id), :clear_current_space)

  def scavenge(campaign_id, resources),
    do: GenServer.call(via(campaign_id), {:scavenge, resources})

  def junker_destroy_card(campaign_id, card_id),
    do: GenServer.call(via(campaign_id), {:junker_destroy_card, card_id})

  def smithy_upgrade_card(campaign_id, card_id),
    do: GenServer.call(via(campaign_id), {:smithy_upgrade_card, card_id})

  def charger_fast(campaign_id, card_id),
    do: GenServer.call(via(campaign_id), {:charger_fast, card_id})

  def charger_turbo(campaign_id, card_ids),
    do: GenServer.call(via(campaign_id), {:charger_turbo, card_ids})

  def charger_trickle(campaign_id, card_id),
    do: GenServer.call(via(campaign_id), {:charger_trickle, card_id})

  # --- Callbacks ---

  @impl true
  def init(opts) do
    campaign_id = Keyword.fetch!(opts, :campaign_id)
    load_save = Keyword.get(opts, :load_save, false)

    state =
      if load_save do
        case CampaignPersistence.load(campaign_id) do
          {:ok, state} -> state
          {:error, _} -> new_campaign(campaign_id)
        end
      else
        new_campaign(campaign_id)
      end

    {:ok, state, @idle_timeout}
  end

  @impl true
  def handle_call(:get_state, _from, state) do
    {:reply, state, state, @idle_timeout}
  end

  @impl true
  def handle_call({:move_to_space, space_id}, _from, state) do
    current_space = Map.fetch!(state.spaces, state.current_space_id)

    cond do
      state.movement_points <= 0 ->
        {:reply, {:error, "No movement points remaining"}, state, @idle_timeout}

      space_id not in current_space.connections ->
        {:reply, {:error, "Cannot move to that space"}, state, @idle_timeout}

      true ->
        target_space = Map.fetch!(state.spaces, space_id)

        new_state = %{state |
          current_space_id: space_id,
          visited_spaces: Enum.uniq([space_id | state.visited_spaces]),
          movement_points: state.movement_points - 1
        }

        case check_space_encounter(target_space) do
          {:combat, enemy_type} ->
            combat_id = Base.encode16(:crypto.strong_rand_bytes(4), case: :lower)
            enemy_cards = enemy_deck_for_type(enemy_type, target_space.danger_rating)

            {:ok, _pid} =
              CombatSupervisor.start_combat(combat_id,
                player_cards: new_state.player_cards,
                player_resources: new_state.player_resources,
                enemy_cards: enemy_cards
              )

            new_state = %{new_state | combat_id: combat_id, movement_points: 0}
            auto_save(new_state)
            broadcast(new_state)
            {:reply, {:combat, combat_id, new_state}, new_state, @idle_timeout}

          :nothing ->
            # Auto-end turn if no movement left
            new_state =
              if new_state.movement_points <= 0,
                do: advance_turn(new_state),
                else: new_state

            auto_save(new_state)
            broadcast(new_state)
            {:reply, {:ok, target_space, new_state}, new_state, @idle_timeout}
        end
    end
  end

  @impl true
  def handle_call(:end_turn, _from, state) do
    new_state = advance_turn(state)
    auto_save(new_state)
    broadcast(new_state)
    {:reply, {:ok, new_state}, new_state, @idle_timeout}
  end

  @impl true
  def handle_call({:complete_combat, player_cards, player_resources, result}, _from, state) do
    updated_spaces =
      if result == :player_wins do
        Map.update!(state.spaces, state.current_space_id, &%{&1 | cleared: true})
      else
        state.spaces
      end

    updated_tiles = sync_tiles_from_spaces(state.tiles, updated_spaces)

    new_state = %{state |
      spaces: updated_spaces,
      tiles: updated_tiles,
      player_cards: player_cards,
      player_resources: player_resources,
      combat_id: nil,
      movement_points: 0
    }

    new_state = advance_turn(new_state)
    auto_save(new_state)
    broadcast(new_state)
    {:reply, {:ok, new_state}, new_state, @idle_timeout}
  end

  @impl true
  def handle_call(:save, _from, state) do
    result = CampaignPersistence.save(state)
    {:reply, result, state, @idle_timeout}
  end

  @impl true
  def handle_call({:rest_repair, card_id}, _from, state) do
    repair_cost = %{metal: 2, wire: 1}

    if has_resources?(state.player_resources, repair_cost) do
      case find_and_repair_card(state.player_cards, card_id) do
        {:ok, updated_cards} ->
          new_resources = deduct_resources(state.player_resources, repair_cost)

          new_state = %{state |
            player_cards: updated_cards,
            player_resources: new_resources
          }

          auto_save(new_state)
          broadcast(new_state)
          {:reply, {:ok, new_state}, new_state, @idle_timeout}

        :not_found ->
          {:reply, {:error, "Card not found"}, state, @idle_timeout}
      end
    else
      {:reply, {:error, "Not enough resources"}, state, @idle_timeout}
    end
  end

  @impl true
  def handle_call({:shop_buy, card_index}, _from, state) do
    shop_inventory = shop_cards_for_node(state)

    if card_index >= 0 and card_index < length(shop_inventory) do
      {card, price} = Enum.at(shop_inventory, card_index)

      if has_resources?(state.player_resources, price) do
        new_card = %{card | id: "shop_#{Base.encode16(:crypto.strong_rand_bytes(3), case: :lower)}"}

        new_state = %{state |
          player_cards: state.player_cards ++ [new_card],
          player_resources: deduct_resources(state.player_resources, price)
        }

        auto_save(new_state)
        broadcast(new_state)
        {:reply, {:ok, new_state}, new_state, @idle_timeout}
      else
        {:reply, {:error, "Not enough resources"}, state, @idle_timeout}
      end
    else
      {:reply, {:error, "Invalid card"}, state, @idle_timeout}
    end
  end

  @impl true
  def handle_call({:scavenge, resources}, _from, state) do
    updated_spaces = Map.update!(state.spaces, state.current_space_id, &%{&1 | cleared: true})
    updated_tiles = sync_tiles_from_spaces(state.tiles, updated_spaces)

    new_resources =
      Enum.reduce(resources, state.player_resources, fn {k, v}, acc ->
        Map.update(acc, k, v, &(&1 + v))
      end)

    new_state = %{state |
      spaces: updated_spaces,
      tiles: updated_tiles,
      player_resources: new_resources
    }

    auto_save(new_state)
    broadcast(new_state)
    {:reply, {:ok, new_state}, new_state, @idle_timeout}
  end

  @impl true
  def handle_call({:junker_destroy_card, card_id}, _from, state) do
    idx = Enum.find_index(state.player_cards, &(&1.id == card_id))

    if idx do
      card = Enum.at(state.player_cards, idx)
      # Mark as destroyed with no overkill for full scrap yield
      destroyed = %{card | damage: :destroyed, current_hp: 0}
      scrap = ScrapLogic.generate_scrap(destroyed)

      new_resources =
        Enum.reduce(scrap, state.player_resources, fn {k, v}, acc ->
          Map.update(acc, k, v, &(&1 + v))
        end)

      updated_spaces = Map.update!(state.spaces, state.current_space_id, &%{&1 | cleared: true})
      updated_tiles = sync_tiles_from_spaces(state.tiles, updated_spaces)

      new_state = %{state |
        player_cards: List.delete_at(state.player_cards, idx),
        player_resources: new_resources,
        spaces: updated_spaces,
        tiles: updated_tiles
      }

      auto_save(new_state)
      broadcast(new_state)
      {:reply, {:ok, scrap, new_state}, new_state, @idle_timeout}
    else
      {:reply, {:error, "Card not found"}, state, @idle_timeout}
    end
  end

  @impl true
  def handle_call({:smithy_upgrade_card, card_id}, _from, state) do
    idx = Enum.find_index(state.player_cards, &(&1.id == card_id))

    if idx do
      card = Enum.at(state.player_cards, idx)

      case UpgradeLogic.upgrade_info(card) do
        nil ->
          {:reply, {:error, "Card cannot be upgraded"}, state, @idle_timeout}

        %{cost: cost} ->
          if has_resources?(state.player_resources, cost) do
            upgraded = UpgradeLogic.apply_upgrade(card)

            updated_spaces = Map.update!(state.spaces, state.current_space_id, &%{&1 | cleared: true})
            updated_tiles = sync_tiles_from_spaces(state.tiles, updated_spaces)

            new_state = %{state |
              player_cards: List.replace_at(state.player_cards, idx, upgraded),
              player_resources: deduct_resources(state.player_resources, cost),
              spaces: updated_spaces,
              tiles: updated_tiles
            }

            auto_save(new_state)
            broadcast(new_state)
            {:reply, {:ok, new_state}, new_state, @idle_timeout}
          else
            {:reply, {:error, "Not enough resources"}, state, @idle_timeout}
          end
      end
    else
      {:reply, {:error, "Card not found"}, state, @idle_timeout}
    end
  end

  @impl true
  def handle_call({:charger_fast, card_id}, _from, state) do
    cost = %{wire: 1, chips: 1}

    if has_resources?(state.player_resources, cost) do
      case recharge_battery(state.player_cards, card_id, :full) do
        {:ok, updated_cards, recharged} ->
          updated_spaces = Map.update!(state.spaces, state.current_space_id, &%{&1 | cleared: true})
          updated_tiles = sync_tiles_from_spaces(state.tiles, updated_spaces)

          new_state = %{state |
            player_cards: updated_cards,
            player_resources: deduct_resources(state.player_resources, cost),
            spaces: updated_spaces,
            tiles: updated_tiles
          }

          auto_save(new_state)
          broadcast(new_state)
          {:reply, {:ok, recharged, new_state}, new_state, @idle_timeout}

        {:error, reason} ->
          {:reply, {:error, reason}, state, @idle_timeout}
      end
    else
      {:reply, {:error, "Not enough resources"}, state, @idle_timeout}
    end
  end

  @impl true
  def handle_call({:charger_turbo, card_ids}, _from, state) when is_list(card_ids) do
    cost = %{wire: 1}

    if length(card_ids) < 1 or length(card_ids) > 2 do
      {:reply, {:error, "Select 1 or 2 batteries"}, state, @idle_timeout}
    else
      if has_resources?(state.player_resources, cost) do
        result =
          Enum.reduce_while(card_ids, {:ok, state.player_cards, 0}, fn cid, {:ok, cards, total} ->
            case recharge_battery(cards, cid, {:add, 2}) do
              {:ok, updated, recharged} -> {:cont, {:ok, updated, total + recharged}}
              {:error, reason} -> {:halt, {:error, reason}}
            end
          end)

        case result do
          {:ok, updated_cards, total_recharged} ->
            updated_spaces = Map.update!(state.spaces, state.current_space_id, &%{&1 | cleared: true})
            updated_tiles = sync_tiles_from_spaces(state.tiles, updated_spaces)

            new_state = %{state |
              player_cards: updated_cards,
              player_resources: deduct_resources(state.player_resources, cost),
              spaces: updated_spaces,
              tiles: updated_tiles
            }

            auto_save(new_state)
            broadcast(new_state)
            {:reply, {:ok, total_recharged, new_state}, new_state, @idle_timeout}

          {:error, reason} ->
            {:reply, {:error, reason}, state, @idle_timeout}
        end
      else
        {:reply, {:error, "Not enough resources"}, state, @idle_timeout}
      end
    end
  end

  @impl true
  def handle_call({:charger_trickle, card_id}, _from, state) do
    case recharge_battery(state.player_cards, card_id, {:add, 1}) do
      {:ok, updated_cards, recharged} ->
        new_state = %{state | player_cards: updated_cards}
        auto_save(new_state)
        broadcast(new_state)
        {:reply, {:ok, recharged, new_state}, new_state, @idle_timeout}

      {:error, reason} ->
        {:reply, {:error, reason}, state, @idle_timeout}
    end
  end

  @impl true
  def handle_call(:clear_current_space, _from, state) do
    updated_spaces = Map.update!(state.spaces, state.current_space_id, &%{&1 | cleared: true})
    updated_tiles = sync_tiles_from_spaces(state.tiles, updated_spaces)
    new_state = %{state | spaces: updated_spaces, tiles: updated_tiles}
    auto_save(new_state)
    broadcast(new_state)
    {:reply, {:ok, new_state}, new_state, @idle_timeout}
  end

  @impl true
  def handle_info(:timeout, state) do
    CampaignPersistence.save(state)
    {:stop, :normal, state}
  end

  # --- Public Helpers (for LiveView) ---

  @doc "Determines charger variant from space label."
  def charger_variant(%{label: "Fast Charger"}), do: :fast
  def charger_variant(%{label: "Turbo Charger"}), do: :turbo
  def charger_variant(%{label: "Trickle Charger"}), do: :trickle
  def charger_variant(_), do: :fast

  def shop_cards_for_node(state) do
    pool = StarterDecks.expanded_card_pool()
    # Seed based on space + campaign so inventory is stable per visit
    seed = :erlang.phash2({state.id, state.current_space_id})
    shuffled = Enum.sort_by(pool, fn card -> :erlang.phash2({seed, card.name}) end)
    cards = Enum.take(shuffled, min(4, length(shuffled)))

    Enum.map(cards, fn card ->
      price = card_price(card, state)
      {card, price}
    end)
  end

  # --- Private ---

  defp new_campaign(campaign_id) do
    seed = :rand.uniform(1_000_000)
    {zones, tiles, spaces, seed} = MapGenerator.generate_map(seed: seed)
    start_space_id = find_start_space(spaces)
    player_cards = StarterDecks.player_deck()
    movement_points = CampaignState.calculate_movement_points(player_cards)

    %CampaignState{
      id: campaign_id,
      seed: seed,
      zones: zones,
      tiles: tiles,
      spaces: spaces,
      current_space_id: start_space_id,
      player_cards: player_cards,
      player_resources: %{},
      visited_spaces: [start_space_id],
      movement_points: movement_points,
      max_movement_points: movement_points,
      turn_number: 1,
      created_at: DateTime.utc_now() |> DateTime.to_iso8601()
    }
  end

  defp find_start_space(spaces) do
    spaces
    |> Enum.find(fn {_id, space} -> space.type == :start end)
    |> elem(0)
  end

  defp check_space_encounter(space) do
    if space.type == :enemy and not space.cleared and space.enemy_type do
      {:combat, space.enemy_type}
    else
      :nothing
    end
  end

  defp enemy_deck_for_type(enemy_type, _danger_rating) do
    StarterDecks.enemy_deck(enemy_type)
  end

  defp advance_turn(state) do
    movement_points = CampaignState.calculate_movement_points(state.player_cards)
    new_turn = state.turn_number + 1

    state = %{state |
      turn_number: new_turn,
      movement_points: movement_points,
      max_movement_points: movement_points
    }

    if rem(new_turn, 5) == 0, do: respawn_enemies(state), else: state
  end

  # Every 5 turns, respawn the closest cleared enemy spawn on the current tile
  # (or an adjacent tile if no cleared enemies on current tile).
  defp respawn_enemies(state) do
    player_tile_id = find_tile_for_space(state.tiles, state.current_space_id)

    # Collect cleared enemy space IDs on the player's current tile
    current_candidates = cleared_enemies_on_tile(state.tiles, player_tile_id)

    # If none on current tile, check immediately adjacent tiles
    candidates =
      if current_candidates == [] do
        adjacent_tile_ids = adjacent_tiles(state.tiles, state.zones, player_tile_id)

        Enum.flat_map(adjacent_tile_ids, fn tid ->
          cleared_enemies_on_tile(state.tiles, tid)
        end)
      else
        current_candidates
      end

    if candidates == [] do
      state
    else
      # BFS from player to find closest candidate(s) by graph distance
      distances = bfs_distances(state.spaces, state.current_space_id, MapSet.new(candidates))
      min_dist = distances |> Map.values() |> Enum.min()
      closest = for {sid, d} <- distances, d == min_dist, do: sid

      # Respawn all equally-closest cleared enemies
      updated_spaces =
        Enum.reduce(closest, state.spaces, fn space_id, spaces ->
          Map.update!(spaces, space_id, &%{&1 | cleared: false})
        end)

      updated_tiles = sync_tiles_from_spaces(state.tiles, updated_spaces)
      count = length(closest)

      Phoenix.PubSub.broadcast(
        Botgrade.PubSub,
        "campaign:#{state.id}",
        {:enemies_respawned, count}
      )

      %{state | spaces: updated_spaces, tiles: updated_tiles}
    end
  end

  defp find_tile_for_space(tiles, space_id) do
    Enum.find_value(tiles, fn {tile_id, tile} ->
      if Map.has_key?(tile.spaces, space_id), do: tile_id
    end)
  end

  defp cleared_enemies_on_tile(tiles, tile_id) do
    case Map.get(tiles, tile_id) do
      nil ->
        []

      tile ->
        tile.spaces
        |> Map.values()
        |> Enum.filter(&(&1.type == :enemy and &1.cleared))
        |> Enum.map(& &1.id)
    end
  end

  defp adjacent_tiles(tiles, zones, tile_id) do
    case Map.get(tiles, tile_id) do
      nil ->
        []

      tile ->
        zone = Map.get(zones, tile.zone_id)

        if zone do
          zone.neighbors
          |> Enum.map(&"tile_#{&1}")
          |> Enum.filter(&Map.has_key?(tiles, &1))
        else
          []
        end
    end
  end

  # BFS from source, returning %{space_id => distance} for all target IDs reached
  defp bfs_distances(spaces, source_id, target_ids) do
    bfs_loop(spaces, :queue.from_list([{source_id, 0}]), MapSet.new([source_id]), target_ids, %{})
  end

  defp bfs_loop(spaces, queue, visited, target_ids, found) do
    case :queue.out(queue) do
      {:empty, _} ->
        found

      {{:value, {current_id, dist}}, rest_queue} ->
        found =
          if MapSet.member?(target_ids, current_id),
            do: Map.put(found, current_id, dist),
            else: found

        remaining_targets = MapSet.difference(target_ids, MapSet.new(Map.keys(found)))

        if MapSet.size(remaining_targets) == 0 do
          found
        else
          neighbors =
            case Map.get(spaces, current_id) do
              nil -> []
              space -> space.connections
            end

          {new_queue, new_visited} =
            Enum.reduce(neighbors, {rest_queue, visited}, fn nid, {q, v} ->
              if MapSet.member?(v, nid) do
                {q, v}
              else
                {:queue.in({nid, dist + 1}, q), MapSet.put(v, nid)}
              end
            end)

          bfs_loop(spaces, new_queue, new_visited, target_ids, found)
        end
    end
  end

  defp sync_tiles_from_spaces(tiles, spaces) do
    Map.new(tiles, fn {tile_id, tile} ->
      updated_tile_spaces =
        Map.new(tile.spaces, fn {space_id, _old_space} ->
          {space_id, Map.fetch!(spaces, space_id)}
        end)

      {tile_id, %{tile | spaces: updated_tile_spaces}}
    end)
  end

  defp auto_save(state) do
    CampaignPersistence.save(state)
  end

  defp broadcast(state) do
    Phoenix.PubSub.broadcast(Botgrade.PubSub, "campaign:#{state.id}", {:campaign_updated, state})
  end

  defp via(campaign_id) do
    {:via, Registry, {Botgrade.Campaign.Registry, campaign_id}}
  end

  defp has_resources?(player_resources, cost) do
    Enum.all?(cost, fn {resource, amount} ->
      Map.get(player_resources, resource, 0) >= amount
    end)
  end

  defp deduct_resources(player_resources, cost) do
    Enum.reduce(cost, player_resources, fn {resource, amount}, acc ->
      Map.update(acc, resource, 0, &max(&1 - amount, 0))
    end)
  end

  defp find_and_repair_card(cards, card_id) do
    idx = Enum.find_index(cards, &(&1.id == card_id && &1.damage == :damaged))

    if idx do
      card = Enum.at(cards, idx)
      max_hp = Map.get(card.properties, :card_hp, 2)
      repaired = %{card | current_hp: max_hp, damage: :intact}
      {:ok, List.replace_at(cards, idx, repaired)}
    else
      :not_found
    end
  end

  defp recharge_battery(cards, card_id, mode) do
    idx = Enum.find_index(cards, &(&1.id == card_id && &1.type == :battery))

    if idx do
      card = Enum.at(cards, idx)
      max_acts = Map.get(card.properties, :max_activations, 5)
      remaining = Map.get(card.properties, :remaining_activations, 0)

      new_remaining =
        case mode do
          :full -> max_acts
          {:add, n} -> min(remaining + n, max_acts)
        end

      recharged = new_remaining - remaining

      updated = %{card | properties: Map.put(card.properties, :remaining_activations, new_remaining)}
      {:ok, List.replace_at(cards, idx, updated), recharged}
    else
      {:error, "Battery not found"}
    end
  end

  defp card_price(card, _state) do
    case card.type do
      :weapon -> %{metal: 3, chips: 1}
      :armor -> %{metal: 2, plastic: 1}
      :battery -> %{wire: 2, metal: 1}
      :capacitor -> %{wire: 2, chips: 1}
      :cpu -> %{chips: 3, wire: 2}
      _ -> %{metal: 2}
    end
  end
end
