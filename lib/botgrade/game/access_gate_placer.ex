defmodule Botgrade.Game.AccessGatePlacer do
  @moduledoc """
  Places access gates on zone boundary edges and assigns access card holders
  to enemies in dead-end zones. Gates block zone-to-zone traversal until the
  player defeats the corresponding card-holding guardian.
  """

  @access_levels ["vermilion", "cerulean", "amaranth", "chartreuse", "puce"]

  @enemy_by_danger %{
    1 => [{"rogue", 1.0}],
    2 => [{"rogue", 0.6}, {"strikebolt", 0.4}],
    3 => [{"rogue", 0.2}, {"strikebolt", 0.3}, {"ironclad", 0.3}, {"hexapod", 0.2}],
    4 => [{"strikebolt", 0.2}, {"ironclad", 0.25}, {"hexapod", 0.25}, {"pyroclast", 0.15}, {"specter", 0.15}],
    5 => [{"ironclad", 0.2}, {"hexapod", 0.25}, {"pyroclast", 0.3}, {"specter", 0.25}],
    6 => [{"ironclad", 0.1}, {"hexapod", 0.2}, {"pyroclast", 0.35}, {"specter", 0.35}],
    7 => [{"hexapod", 0.15}, {"pyroclast", 0.4}, {"specter", 0.45}],
    8 => [{"pyroclast", 0.45}, {"specter", 0.55}]
  }

  @guardian_labels ["Vermilion Guardian", "Cerulean Guardian", "Amaranth Guardian",
                    "Chartreuse Guardian", "Puce Guardian"]

  @doc """
  Places access gates on bridge edges and card-holding enemies in dead-end zones.
  Returns updated `{tiles, spaces}`.
  """
  @spec place_gates_and_cards(map(), map(), map(), integer()) :: {map(), map()}
  def place_gates_and_cards(zones, tiles, spaces, seed) do
    # Re-seed RNG for deterministic placement
    :rand.seed(:exsss, {seed + 100, seed + 101, seed + 102})

    start_zone_id = "zone_0_2"
    exit_zone_id = "zone_7_2"

    # Step 1: Build adjacency graph
    adj = build_adjacency(zones)

    # Step 2: Find shortest path from start to exit
    main_path = bfs_path(adj, start_zone_id, exit_zone_id)

    # Step 3: Find bridge edges
    bridges = find_bridges(adj)

    # Step 4: Find dead-end zones (1 neighbor only, not start/exit)
    dead_end_zones =
      zones
      |> Map.values()
      |> Enum.filter(fn z ->
        length(z.neighbors) == 1 and z.id != start_zone_id and z.id != exit_zone_id
      end)
      |> Enum.map(& &1.id)

    # Fallback: zones with 2 neighbors if not enough dead-ends
    fallback_zones =
      if length(dead_end_zones) < 1 do
        zones
        |> Map.values()
        |> Enum.filter(fn z ->
          length(z.neighbors) == 2 and z.id != start_zone_id and z.id != exit_zone_id
        end)
        |> Enum.sort_by(fn z -> -bfs_distance(adj, start_zone_id, z.id) end)
        |> Enum.map(& &1.id)
      else
        []
      end

    candidate_holders = dead_end_zones ++ fallback_zones

    # Step 5: Select gate edges
    gate_edges = select_gate_edges(adj, bridges, main_path, exit_zone_id, length(candidate_holders))

    # Step 6: Pair gates to card holders
    pairings = pair_gates_to_holders(adj, gate_edges, candidate_holders, start_zone_id)

    # Step 7: Apply to spaces
    apply_pairings(pairings, zones, tiles, spaces)
  end

  # --- Zone adjacency graph ---

  defp build_adjacency(zones) do
    Map.new(zones, fn {zone_id, zone} -> {zone_id, zone.neighbors} end)
  end

  # --- BFS shortest path ---

  defp bfs_path(adj, from, to) do
    do_bfs_path(:queue.from_list([{from, [from]}]), MapSet.new([from]), adj, to)
  end

  defp do_bfs_path(queue, visited, adj, target) do
    case :queue.out(queue) do
      {:empty, _} ->
        []

      {{:value, {current, path}}, rest} ->
        if current == target do
          path
        else
          neighbors = Map.get(adj, current, [])

          {new_queue, new_visited} =
            Enum.reduce(neighbors, {rest, visited}, fn n, {q, v} ->
              if MapSet.member?(v, n) do
                {q, v}
              else
                {:queue.in({n, path ++ [n]}, q), MapSet.put(v, n)}
              end
            end)

          do_bfs_path(new_queue, new_visited, adj, target)
        end
    end
  end

  defp bfs_distance(adj, from, to) do
    path = bfs_path(adj, from, to)
    max(0, length(path) - 1)
  end

  # --- Tarjan's bridge detection ---

  defp find_bridges(adj) do
    all_nodes = Map.keys(adj)

    state = %{
      disc: %{},
      low: %{},
      timer: 0,
      bridges: []
    }

    state =
      Enum.reduce(all_nodes, state, fn node, acc ->
        if Map.has_key?(acc.disc, node) do
          acc
        else
          bridge_dfs(node, nil, adj, acc)
        end
      end)

    # Normalize bridge edges as sorted tuples
    Enum.map(state.bridges, fn {a, b} ->
      if a < b, do: {a, b}, else: {b, a}
    end)
    |> Enum.uniq()
  end

  defp bridge_dfs(node, parent, adj, state) do
    state = %{state |
      disc: Map.put(state.disc, node, state.timer),
      low: Map.put(state.low, node, state.timer),
      timer: state.timer + 1
    }

    neighbors = Map.get(adj, node, [])

    Enum.reduce(neighbors, state, fn neighbor, acc ->
      cond do
        neighbor == parent ->
          acc

        Map.has_key?(acc.disc, neighbor) ->
          # Back edge: update low
          new_low = min(Map.fetch!(acc.low, node), Map.fetch!(acc.disc, neighbor))
          %{acc | low: Map.put(acc.low, node, new_low)}

        true ->
          # Tree edge: recurse
          acc = bridge_dfs(neighbor, node, adj, acc)
          neighbor_low = Map.fetch!(acc.low, neighbor)
          node_low = min(Map.fetch!(acc.low, node), neighbor_low)
          acc = %{acc | low: Map.put(acc.low, node, node_low)}

          # Check if this is a bridge
          if neighbor_low > Map.fetch!(acc.disc, node) do
            %{acc | bridges: [{node, neighbor} | acc.bridges]}
          else
            acc
          end
      end
    end)
  end

  # --- Gate edge selection ---

  defp select_gate_edges(_adj, bridges, main_path, exit_zone_id, max_holders) do
    # Build set of edges on the main path
    main_path_edges =
      main_path
      |> Enum.chunk_every(2, 1, :discard)
      |> Enum.map(fn [a, b] -> if a < b, do: {a, b}, else: {b, a} end)
      |> MapSet.new()

    # The exit edge: the edge leading into the exit zone on the main path
    exit_edge =
      main_path_edges
      |> Enum.find(fn {a, b} -> a == exit_zone_id or b == exit_zone_id end)

    # Bridges on the main path (excluding the exit edge to add it separately)
    main_path_bridges =
      bridges
      |> Enum.filter(&MapSet.member?(main_path_edges, &1))
      |> Enum.reject(&(&1 == exit_edge))

    # Bridges NOT on the main path
    other_bridges =
      bridges
      |> Enum.reject(&MapSet.member?(main_path_edges, &1))

    # Build gate list: exit edge first, then main path bridges, then other bridges
    candidates =
      (if exit_edge, do: [exit_edge], else: []) ++
      Enum.shuffle(main_path_bridges) ++
      Enum.shuffle(other_bridges)

    # If no exit edge found as a bridge, force-add it anyway
    candidates =
      if exit_edge && exit_edge not in candidates do
        [exit_edge | candidates]
      else
        if exit_edge == nil do
          # Force create an exit gate from the last main path edge
          forced = main_path_edges |> Enum.find(fn {a, b} -> a == exit_zone_id or b == exit_zone_id end)
          if forced, do: [forced | candidates], else: candidates
        else
          candidates
        end
      end

    # Also add non-bridge main path edges as fallback if we have holders but few bridges
    fallback_edges =
      main_path_edges
      |> Enum.reject(fn e -> e in candidates end)
      |> Enum.reject(fn {a, b} ->
        # Don't gate the start zone
        a == "zone_0_2" or b == "zone_0_2"
      end)
      |> Enum.shuffle()

    all_candidates = candidates ++ fallback_edges

    # Cap: at most min(max_holders, 4, length(access_levels)) gates
    max_gates = min(max_holders, min(4, length(@access_levels)))
    max_gates = max(max_gates, 1)

    # Validate gates: ensure they don't create unreachable card holders
    # For now, take up to max_gates
    Enum.take(all_candidates, max_gates)
    |> Enum.uniq()
  end

  # --- Pairing gates to card holders ---

  defp pair_gates_to_holders(adj, gate_edges, candidate_holders, start_zone_id) do
    # For each gate, find which side contains start, then pick a holder on that side
    {pairings, _used} =
      gate_edges
      |> Enum.with_index()
      |> Enum.reduce({[], MapSet.new()}, fn {{zone_a, zone_b} = edge, idx}, {acc, used} ->
        level = Enum.at(@access_levels, idx)

        if level == nil do
          {acc, used}
        else
          # Find start-side of the gate
          start_side = start_side_zone(adj, edge, start_zone_id)

          # Find candidate holders on the start side, not yet used
          available =
            candidate_holders
            |> Enum.reject(&MapSet.member?(used, &1))
            |> Enum.filter(fn holder_id ->
              # Check reachability from start without crossing this gate edge
              reachable_without_edge?(adj, start_zone_id, holder_id, {zone_a, zone_b})
            end)

          # Prefer holders at least 2 hops from the gate
          {close, far} =
            Enum.split_with(available, fn h ->
              bfs_distance(adj, h, zone_a) < 2 and bfs_distance(adj, h, zone_b) < 2
            end)

          chosen =
            case {far, close} do
              {[_ | _], _} -> Enum.random(far)
              {[], [_ | _]} -> Enum.random(close)
              {[], []} -> nil
            end

          if chosen do
            pairing = %{
              level: level,
              gate_edge: edge,
              holder_zone_id: chosen,
              start_side: start_side
            }

            {[pairing | acc], MapSet.put(used, chosen)}
          else
            # No holder available - still place the gate but without a card holder
            # This shouldn't happen with proper candidate selection, but handle gracefully
            {acc, used}
          end
        end
      end)

    Enum.reverse(pairings)
  end

  # Determine which zone of the edge is on the start side
  defp start_side_zone(adj, {zone_a, zone_b}, start_zone_id) do
    if reachable_without_edge?(adj, start_zone_id, zone_a, {zone_a, zone_b}) do
      zone_a
    else
      zone_b
    end
  end

  # Check if `target` is reachable from `source` in the zone graph
  # with the given edge removed
  defp reachable_without_edge?(adj, source, target, {edge_a, edge_b}) do
    # BFS with edge removed
    do_reachable_bfs(
      :queue.from_list([source]),
      MapSet.new([source]),
      adj,
      target,
      {edge_a, edge_b}
    )
  end

  defp do_reachable_bfs(queue, visited, adj, target, removed_edge) do
    case :queue.out(queue) do
      {:empty, _} ->
        false

      {{:value, current}, rest} ->
        if current == target do
          true
        else
          neighbors =
            Map.get(adj, current, [])
            |> Enum.reject(fn n ->
              edge = if current < n, do: {current, n}, else: {n, current}
              edge == removed_edge
            end)

          {new_queue, new_visited} =
            Enum.reduce(neighbors, {rest, visited}, fn n, {q, v} ->
              if MapSet.member?(v, n), do: {q, v}, else: {:queue.in(n, q), MapSet.put(v, n)}
            end)

          do_reachable_bfs(new_queue, new_visited, adj, target, removed_edge)
        end
    end
  end

  # --- Apply pairings to tiles/spaces ---

  defp apply_pairings(pairings, zones, tiles, spaces) do
    Enum.reduce(pairings, {tiles, spaces}, fn pairing, {t, s} ->
      {t, s} = apply_gate(pairing, zones, t, s)
      {t, s} = apply_card_holder(pairing, zones, t, s)
      {t, s}
    end)
  end

  defp apply_gate(%{level: level, gate_edge: {zone_a, zone_b}}, zones, tiles, spaces) do
    # Find the direction between zone_a and zone_b
    za = Map.fetch!(zones, zone_a)
    zb = Map.fetch!(zones, zone_b)
    dir_a_to_b = direction_between(za.grid_pos, zb.grid_pos)
    dir_b_to_a = opposite_dir(dir_a_to_b)

    tile_a = Map.get(tiles, "tile_#{zone_a}")
    tile_b = Map.get(tiles, "tile_#{zone_b}")

    gate_label = "#{String.capitalize(level)} Gate"

    # Update edge connector in tile A (direction toward B)
    ec_a_id = tile_a && Map.get(tile_a.edge_connectors, dir_a_to_b)
    # Update edge connector in tile B (direction toward A)
    ec_b_id = tile_b && Map.get(tile_b.edge_connectors, dir_b_to_a)

    spaces =
      spaces
      |> maybe_update_gate_space(ec_a_id, level, gate_label)
      |> maybe_update_gate_space(ec_b_id, level, gate_label)

    # Sync tiles from spaces
    tiles = sync_tiles(tiles, spaces)

    {tiles, spaces}
  end

  defp maybe_update_gate_space(spaces, nil, _level, _label), do: spaces

  defp maybe_update_gate_space(spaces, space_id, level, label) do
    Map.update!(spaces, space_id, fn space ->
      %{space | access_level: level, label: label}
    end)
  end

  defp apply_card_holder(%{level: level, holder_zone_id: holder_zone_id}, zones, tiles, spaces) do
    zone = Map.fetch!(zones, holder_zone_id)
    tile = Map.get(tiles, "tile_#{holder_zone_id}")

    if tile == nil do
      {tiles, spaces}
    else
      # Find a dead-end space in this tile (scavenge type = was a dead end)
      # Or any non-special space if no dead-ends
      tile_space_ids = Map.keys(tile.spaces)

      dead_end_space =
        tile_space_ids
        |> Enum.map(&Map.fetch!(spaces, &1))
        |> Enum.filter(fn s ->
          s.type == :scavenge and not s.cleared
        end)
        |> List.first()

      # Fallback: any empty/passage space
      target_space =
        dead_end_space ||
          tile_space_ids
          |> Enum.map(&Map.fetch!(spaces, &1))
          |> Enum.filter(fn s ->
            s.type in [:empty, :scavenge] and not s.cleared and
              s.id != "#{holder_zone_id}_center"
          end)
          |> Enum.sort_by(fn s -> length(s.connections) end)
          |> List.first()

      # Last resort: any non-edge, non-center space
      target_space =
        target_space ||
          tile_space_ids
          |> Enum.map(&Map.fetch!(spaces, &1))
          |> Enum.filter(fn s ->
            s.type not in [:edge_connector, :start, :exit] and
              s.id != "#{holder_zone_id}_center"
          end)
          |> Enum.sort_by(fn s -> length(s.connections) end)
          |> List.first()

      if target_space == nil do
        {tiles, spaces}
      else
        level_idx = Enum.find_index(@access_levels, &(&1 == level))
        guardian_label = Enum.at(@guardian_labels, level_idx || 0, "Guardian")
        enemy_type = pick_enemy_type(zone.danger_rating)

        updated_space = %{target_space |
          type: :enemy,
          enemy_type: enemy_type,
          enemy_behavior: :stationary,
          encounter_range: 1,
          danger_rating: zone.danger_rating,
          cleared: false,
          holds_access_card: level,
          label: guardian_label
        }

        spaces = Map.put(spaces, updated_space.id, updated_space)
        tiles = sync_tiles(tiles, spaces)

        {tiles, spaces}
      end
    end
  end

  # --- Helpers ---

  defp direction_between({c1, r1}, {c2, r2}) do
    cond do
      c2 == c1 + 1 and r2 == r1 -> :east
      c2 == c1 - 1 and r2 == r1 -> :west
      r2 == r1 - 1 and c2 == c1 -> :north
      r2 == r1 + 1 and c2 == c1 -> :south
      true -> :east
    end
  end

  defp opposite_dir(:north), do: :south
  defp opposite_dir(:south), do: :north
  defp opposite_dir(:east), do: :west
  defp opposite_dir(:west), do: :east

  defp pick_enemy_type(danger_rating) do
    weights = Map.get(@enemy_by_danger, danger_rating, [{"rogue", 1.0}])
    total = weights |> Enum.map(&elem(&1, 1)) |> Enum.sum()
    roll = :rand.uniform() * total

    weights
    |> Enum.reduce_while(0.0, fn {item, weight}, acc ->
      new_acc = acc + weight
      if new_acc >= roll, do: {:halt, item}, else: {:cont, new_acc}
    end)
  end

  defp sync_tiles(tiles, spaces) do
    Map.new(tiles, fn {tile_id, tile} ->
      updated_tile_spaces =
        Map.new(tile.spaces, fn {space_id, _old} ->
          {space_id, Map.fetch!(spaces, space_id)}
        end)

      {tile_id, %{tile | spaces: updated_tile_spaces}}
    end)
  end
end
