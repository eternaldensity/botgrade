defmodule Botgrade.Game.TileGenerator do
  @moduledoc """
  Generates a tile with 5-10 internal spaces for a zone.
  Each tile has a branching path connecting its passable sides
  (determined by which neighboring zones exist).
  """

  alias Botgrade.Game.{Space, Tile, Zone}

  @cell_width 400.0
  @cell_height 350.0

  @space_type_weights [enemy: 50, shop: 15, rest: 15, event: 20, junker: 10, smithy: 8, charger: 12]

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

  @space_labels %{
    enemy: ["Hostile Contact", "Enemy Patrol", "Rogue Bot", "Ambush Point", "Danger Zone"],
    shop: ["Scrap Trader", "Parts Dealer", "Salvage Shop", "Component Market"],
    rest: ["Shelter", "Repair Bay", "Safe Zone", "Maintenance Hub"],
    event: ["Signal Source", "Data Cache", "Anomaly", "Unknown Contact", "Wreckage Site"],
    start: ["Entry Point"],
    exit: ["Research Lab"],
    scavenge: ["Salvage Pile", "Scrap Cache", "Supply Stash", "Wreckage"],
    junker: ["Junker", "Chop Shop", "Scrap Forge", "Disassembly Pit"],
    smithy: ["Smithy", "Forge Works", "Upgrade Bay", "Tinker's Den"],
    charger: ["Fast Charger", "Turbo Charger", "Trickle Charger"],
    empty_passage: ["Passage", "Corridor", "Open Street", "Walkway"],
    empty_junction: ["Junction", "Crossroads", "Intersection", "Hub"],
    edge_connector: ["Zone Border"]
  }

  @doc """
  Generate a tile for the given zone. `neighbor_dirs` is a list of directions
  (:north, :south, :east, :west) that have adjacent zones.
  `is_start` and `is_exit` mark the start/exit zones.
  """
  @spec generate_tile(Zone.t(), [atom()], boolean(), boolean()) :: Tile.t()
  def generate_tile(%Zone{} = zone, neighbor_dirs, is_start, is_exit) do
    {col, row} = zone.grid_pos
    tile_id = "tile_#{zone.id}"
    base_x = col * @cell_width
    base_y = row * @cell_height

    # Step 1: Place edge connector spaces at midpoints of connected sides
    edge_spaces = build_edge_connectors(zone.id, neighbor_dirs, base_x, base_y)

    # Step 2: Place center space
    center = build_center_space(zone, base_x, base_y, is_start, is_exit)

    # Step 3: Build branching path from edge connectors through center
    {path_spaces, connections} =
      build_internal_path(zone, edge_spaces, center, base_x, base_y, neighbor_dirs)

    # Step 4: Combine all spaces
    all_spaces_list = edge_spaces ++ [center] ++ path_spaces

    # Step 5: Assign types to non-edge, non-center spaces
    all_spaces_list = assign_space_types(all_spaces_list, zone, is_start, is_exit)

    # Step 6: Apply connections
    all_spaces_list = apply_connections(all_spaces_list, connections)

    # Step 7: Fix empty space labels based on actual connection count
    all_spaces_list = fix_empty_labels(all_spaces_list)

    # Build space map
    spaces = Map.new(all_spaces_list, fn s -> {s.id, s} end)

    # Build edge connector map
    edge_connector_map =
      Map.new(neighbor_dirs, fn dir ->
        ec = Enum.find(edge_spaces, fn s -> s.label == edge_label(dir) end)
        {dir, ec && ec.id}
      end)

    # Fill any missing directions with nil
    edge_connector_map =
      Enum.reduce([:north, :south, :east, :west], edge_connector_map, fn dir, acc ->
        Map.put_new(acc, dir, nil)
      end)

    %Tile{
      id: tile_id,
      zone_id: zone.id,
      spaces: spaces,
      edge_connectors: edge_connector_map,
      bounds: {base_x, base_y, @cell_width, @cell_height}
    }
  end

  # Build edge connector spaces at the midpoints of each connected side
  defp build_edge_connectors(zone_id, neighbor_dirs, base_x, base_y) do
    Enum.map(neighbor_dirs, fn dir ->
      {x, y} = edge_position(dir, base_x, base_y)

      %Space{
        id: "#{zone_id}_ec_#{dir}",
        type: :edge_connector,
        position: {x, y},
        zone_id: zone_id,
        label: edge_label(dir),
        danger_rating: 1,
        cleared: true
      }
    end)
  end

  defp edge_position(:north, base_x, base_y),
    do: {base_x + @cell_width / 2, base_y + 25.0}

  defp edge_position(:south, base_x, base_y),
    do: {base_x + @cell_width / 2, base_y + @cell_height - 25.0}

  defp edge_position(:east, base_x, base_y),
    do: {base_x + @cell_width - 25.0, base_y + @cell_height / 2}

  defp edge_position(:west, base_x, base_y),
    do: {base_x + 25.0, base_y + @cell_height / 2}

  defp edge_label(:north), do: "North Border"
  defp edge_label(:south), do: "South Border"
  defp edge_label(:east), do: "East Border"
  defp edge_label(:west), do: "West Border"

  # Build the center space
  defp build_center_space(zone, base_x, base_y, is_start, is_exit) do
    cx = base_x + @cell_width / 2
    cy = base_y + @cell_height / 2

    {type, label} =
      cond do
        is_start -> {:start, Enum.random(@space_labels[:start])}
        is_exit -> {:exit, Enum.random(@space_labels[:exit])}
        true -> {:empty, "Passage"}
      end

    %Space{
      id: "#{zone.id}_center",
      type: type,
      position: {cx, cy},
      zone_id: zone.id,
      label: label,
      danger_rating: zone.danger_rating,
      cleared: is_start
    }
  end

  # Build intermediate spaces along the internal path.
  # For each edge connector, create 1 intermediate space between it and center.
  # If we have >2 connectors, we get branches naturally.
  # Then add extra spaces to reach 5-8 total.
  defp build_internal_path(zone, edge_spaces, center, base_x, base_y, _neighbor_dirs) do
    # Create one intermediate per edge connector
    intermediates =
      Enum.map(edge_spaces, fn ec ->
        {ecx, ecy} = ec.position
        {cx, cy} = center.position
        # Place intermediate at 40% from edge connector toward center (with jitter)
        t = 0.4 + (:rand.uniform() * 0.2 - 0.1)
        ix = ecx + (cx - ecx) * t + jitter(10)
        iy = ecy + (cy - ecy) * t + jitter(10)
        # Clamp within tile bounds
        ix = clamp(ix, base_x + 35, base_x + @cell_width - 35)
        iy = clamp(iy, base_y + 35, base_y + @cell_height - 35)

        %Space{
          id: "#{zone.id}_mid_#{ec.id |> String.split("_ec_") |> List.last()}",
          type: :empty,
          position: {ix, iy},
          zone_id: zone.id,
          label: "Passage",
          danger_rating: zone.danger_rating
        }
      end)

    # Basic connections: edge_connector <-> intermediate <-> center
    base_connections =
      Enum.zip(edge_spaces, intermediates)
      |> Enum.flat_map(fn {ec, mid} ->
        [{ec.id, mid.id}, {mid.id, center.id}]
      end)

    # Calculate how many extra spaces we need to reach 5-8 total
    current_count = length(edge_spaces) + 1 + length(intermediates)
    target = Enum.random(5..10)
    extra_needed = max(0, target - current_count)

    # Add extra spaces branching off existing intermediates or center
    {extra_spaces, extra_connections} =
      build_extra_spaces(zone, intermediates ++ [center], extra_needed, base_x, base_y)

    all_path_spaces = intermediates ++ extra_spaces
    all_connections = base_connections ++ extra_connections

    {all_path_spaces, all_connections}
  end

  # Add extra spaces to reach target count, branching off existing spaces
  defp build_extra_spaces(_zone, _anchor_spaces, 0, _base_x, _base_y), do: {[], []}

  defp build_extra_spaces(zone, anchor_spaces, count, base_x, base_y) do
    Enum.reduce(1..count, {[], []}, fn i, {spaces_acc, conns_acc} ->
      # Pick a random anchor to branch from
      all_anchors = anchor_spaces ++ spaces_acc
      anchor = Enum.random(all_anchors)
      {ax, ay} = anchor.position

      # Place in a random direction from anchor
      angle = :rand.uniform() * 2 * :math.pi()
      dist = 55.0 + :rand.uniform() * 40.0
      nx = clamp(ax + :math.cos(angle) * dist, base_x + 35, base_x + @cell_width - 35)
      ny = clamp(ay + :math.sin(angle) * dist, base_y + 35, base_y + @cell_height - 35)

      space = %Space{
        id: "#{zone.id}_extra_#{i}",
        type: :empty,
        position: {nx, ny},
        zone_id: zone.id,
        label: "Passage",
        danger_rating: zone.danger_rating
      }

      {spaces_acc ++ [space], conns_acc ++ [{anchor.id, space.id}]}
    end)
  end

  # Assign meaningful types to non-edge, non-center spaces
  defp assign_space_types(spaces, zone, is_start, is_exit) do
    {fixed, assignable} =
      Enum.split_with(spaces, fn s ->
        s.type in [:edge_connector, :start, :exit] or
          (s.type == :empty and s.id == "#{zone.id}_center" and (is_start or is_exit))
      end)

    # Guarantee at least one enemy space per zone (if danger > 0)
    {with_enemy, rest} = ensure_one_enemy(assignable, zone)

    # Assign remaining types with weighted random
    assigned_rest =
      Enum.map(rest, fn space ->
        # 50% chance to stay empty, 50% chance to get a type
        if :rand.uniform() < 0.5 do
          space
        else
          assign_random_type(space, zone)
        end
      end)

    fixed ++ with_enemy ++ assigned_rest
  end

  defp ensure_one_enemy(spaces, zone) do
    if spaces == [] do
      {[], []}
    else
      # Pick one random space to be an enemy
      idx = :rand.uniform(length(spaces)) - 1
      enemy_space = Enum.at(spaces, idx)
      enemy_type = weighted_random(@enemy_by_danger[zone.danger_rating] || [{"rogue", 1.0}])

      enemy_space = %{
        enemy_space
        | type: :enemy,
          label: Enum.random(@space_labels[:enemy]),
          enemy_type: enemy_type,
          enemy_behavior: :stationary,
          encounter_range: 1,
          danger_rating: zone.danger_rating
      }

      rest = List.delete_at(spaces, idx)
      {[enemy_space], rest}
    end
  end

  defp assign_random_type(space, zone) do
    type = weighted_random_atom(@space_type_weights)

    case type do
      :enemy ->
        enemy_type = weighted_random(@enemy_by_danger[zone.danger_rating] || [{"rogue", 1.0}])

        %{
          space
          | type: :enemy,
            label: Enum.random(@space_labels[:enemy]),
            enemy_type: enemy_type,
            enemy_behavior: :stationary,
            encounter_range: 1,
            danger_rating: zone.danger_rating
        }

      other ->
        %{space | type: other, label: Enum.random(@space_labels[other])}
    end
  end

  # Assign labels to empty spaces based on connection count.
  # Dead-end empties become scavenge spots (rewarding exploration).
  defp fix_empty_labels(spaces) do
    Enum.map(spaces, fn space ->
      if space.type == :empty do
        case length(space.connections) do
          n when n <= 1 ->
            %{space | type: :scavenge, label: Enum.random(@space_labels[:scavenge])}

          2 ->
            %{space | label: Enum.random(@space_labels[:empty_passage])}

          _ ->
            %{space | label: Enum.random(@space_labels[:empty_junction])}
        end
      else
        space
      end
    end)
  end

  # Apply bidirectional connections to spaces
  defp apply_connections(spaces, connections) do
    # Build adjacency map
    adj =
      Enum.reduce(connections, %{}, fn {a, b}, acc ->
        acc
        |> Map.update(a, [b], &[b | &1])
        |> Map.update(b, [a], &[a | &1])
      end)

    Enum.map(spaces, fn space ->
      conns = Map.get(adj, space.id, []) |> Enum.uniq()
      %{space | connections: Enum.uniq(space.connections ++ conns)}
    end)
  end

  # --- Helpers ---

  defp jitter(range) do
    :rand.uniform() * range * 2 - range
  end

  defp clamp(value, min_val, max_val) do
    value |> max(min_val) |> min(max_val)
  end

  defp weighted_random(weighted_list) do
    total = weighted_list |> Enum.map(&elem(&1, 1)) |> Enum.sum()
    roll = :rand.uniform() * total

    weighted_list
    |> Enum.reduce_while(0.0, fn {item, weight}, acc ->
      new_acc = acc + weight
      if new_acc >= roll, do: {:halt, item}, else: {:cont, new_acc}
    end)
  end

  defp weighted_random_atom(weights) do
    total = weights |> Enum.map(&elem(&1, 1)) |> Enum.sum()
    roll = :rand.uniform() * total

    weights
    |> Enum.reduce_while(0, fn {type, weight}, acc ->
      new_acc = acc + weight
      if new_acc >= roll, do: {:halt, type}, else: {:cont, new_acc}
    end)
  end
end
