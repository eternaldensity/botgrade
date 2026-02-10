defmodule Botgrade.Game.MapGenerator do
  @moduledoc """
  Orchestrates campaign map generation.
  Seed → zones (ZoneGenerator) → tiles (TileGenerator) → linked spaces.
  """

  alias Botgrade.Game.{ZoneGenerator, TileGenerator, Zone}

  @start_zone_pos {0, 1}
  @exit_zone_pos {7, 1}

  @doc """
  Generate a complete campaign map.

  Options:
    - `:seed` - integer seed for reproducible generation (default: random)
    - `:grid_cols` - zone grid width (default 8)
    - `:grid_rows` - zone grid height (default 3)

  Returns `{zones, tiles, spaces, seed}`.
  """
  @spec generate_map(keyword()) ::
          {%{String.t() => Zone.t()}, map(), map(), integer()}
  def generate_map(opts \\ []) do
    seed = Keyword.get(opts, :seed, :rand.uniform(1_000_000))

    # Step 1: Generate zone layout
    zones = ZoneGenerator.generate_zones(seed, opts)

    # Step 2: Generate tiles for each zone
    tiles = generate_all_tiles(zones)

    # Step 3: Link edge connectors between adjacent tiles
    tiles = link_edge_connectors(tiles, zones)

    # Step 4: Build flat space lookup
    spaces = build_space_index(tiles)

    {zones, tiles, spaces, seed}
  end

  # Generate a tile for each zone
  defp generate_all_tiles(zones) do
    Map.new(zones, fn {_zone_id, zone} ->
      neighbor_dirs = compute_neighbor_dirs(zone, zones)
      is_start = zone.grid_pos == @start_zone_pos
      is_exit = zone.grid_pos == @exit_zone_pos

      tile = TileGenerator.generate_tile(zone, neighbor_dirs, is_start, is_exit)
      {tile.id, tile}
    end)
  end

  # Determine which cardinal directions have neighboring zones
  defp compute_neighbor_dirs(%Zone{} = zone, zones) do
    {col, row} = zone.grid_pos

    direction_offsets = [
      {:north, {col, row - 1}},
      {:south, {col, row + 1}},
      {:east, {col + 1, row}},
      {:west, {col - 1, row}}
    ]

    direction_offsets
    |> Enum.filter(fn {_dir, pos} ->
      Enum.any?(zones, fn {_id, z} -> z.grid_pos == pos end)
    end)
    |> Enum.map(&elem(&1, 0))
  end

  # Link edge connector spaces between adjacent tiles
  defp link_edge_connectors(tiles, zones) do
    # For each zone pair that is adjacent, link their edge connectors
    zone_list = Map.values(zones)

    adjacency_pairs =
      for z1 <- zone_list,
          z2 <- zone_list,
          z1.id < z2.id,
          dir = adjacent_direction(z1, z2),
          dir != nil,
          do: {z1, z2, dir}

    Enum.reduce(adjacency_pairs, tiles, fn {z1, z2, dir}, acc ->
      opposite = opposite_dir(dir)
      tile1_id = "tile_#{z1.id}"
      tile2_id = "tile_#{z2.id}"

      tile1 = Map.get(acc, tile1_id)
      tile2 = Map.get(acc, tile2_id)

      if tile1 && tile2 do
        ec1_id = Map.get(tile1.edge_connectors, dir)
        ec2_id = Map.get(tile2.edge_connectors, opposite)

        if ec1_id && ec2_id do
          # Add cross-tile connections
          acc
          |> update_space_connection(tile1_id, ec1_id, ec2_id)
          |> update_space_connection(tile2_id, ec2_id, ec1_id)
        else
          acc
        end
      else
        acc
      end
    end)
  end

  # Determine if z1 is adjacent to z2 and in which direction
  defp adjacent_direction(z1, z2) do
    {c1, r1} = z1.grid_pos
    {c2, r2} = z2.grid_pos

    cond do
      c2 == c1 + 1 and r2 == r1 -> :east
      c2 == c1 - 1 and r2 == r1 -> :west
      r2 == r1 - 1 and c2 == c1 -> :north
      r2 == r1 + 1 and c2 == c1 -> :south
      true -> nil
    end
  end

  defp opposite_dir(:north), do: :south
  defp opposite_dir(:south), do: :north
  defp opposite_dir(:east), do: :west
  defp opposite_dir(:west), do: :east

  # Add a connection to a space within a tile
  defp update_space_connection(tiles, tile_id, space_id, target_id) do
    Map.update!(tiles, tile_id, fn tile ->
      updated_spaces =
        Map.update!(tile.spaces, space_id, fn space ->
          %{space | connections: Enum.uniq([target_id | space.connections])}
        end)

      %{tile | spaces: updated_spaces}
    end)
  end

  # Build a flat %{space_id => Space} from all tiles
  defp build_space_index(tiles) do
    tiles
    |> Map.values()
    |> Enum.flat_map(fn tile -> Map.values(tile.spaces) end)
    |> Map.new(fn space -> {space.id, space} end)
  end
end
