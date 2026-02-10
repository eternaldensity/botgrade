defmodule Botgrade.Game.ZoneGenerator do
  @moduledoc """
  Generates a grid of zones for the campaign map from a seed.
  Produces a 4x3 grid with ~75% fill, adjacency constraints,
  and a danger gradient from start (left) to exit (right).
  """

  alias Botgrade.Game.Zone

  @zone_types [:industrial, :residential, :commercial]
  @grid_cols 4
  @grid_rows 3

  @doc """
  Generate a zone grid from a seed. Returns `%{zone_id => Zone.t()}`.

  Options:
    - `:grid_cols` - grid width (default 4)
    - `:grid_rows` - grid height (default 3)
  """
  @spec generate_zones(integer(), keyword()) :: %{String.t() => Zone.t()}
  def generate_zones(seed, opts \\ []) do
    cols = Keyword.get(opts, :grid_cols, @grid_cols)
    rows = Keyword.get(opts, :grid_rows, @grid_rows)

    # Seed the RNG deterministically
    :rand.seed(:exsss, {seed, seed + 1, seed + 2})

    # Step 1: Determine which grid cells are filled
    cells = generate_cell_layout(cols, rows)

    # Step 2: Assign zone types respecting adjacency rules
    cells_with_types = assign_zone_types(cells, cols, rows)

    # Step 3: Assign danger ratings with gradient
    cells_with_danger = assign_danger_ratings(cells_with_types, cols)

    # Step 4: Build Zone structs with neighbor lists
    build_zones(cells_with_danger, cols, rows)
  end

  # Generate which cells are filled. Start and exit are always filled.
  # Fills ~75% of remaining cells, ensuring connectivity.
  defp generate_cell_layout(cols, rows) do
    # Always fill start {0, mid} and exit {cols-1, mid}
    mid = div(rows, 2)
    required = [{0, mid}, {cols - 1, mid}]

    # Generate candidate cells (all positions except required)
    all_cells =
      for col <- 0..(cols - 1), row <- 0..(rows - 1), {col, row} not in required, do: {col, row}

    # Fill ~75% of remaining cells
    fill_count = round(length(all_cells) * 0.75)
    filled = Enum.take_random(all_cells, fill_count)
    all_filled = MapSet.new(required ++ filled)

    # Ensure path connectivity from start to exit using BFS
    ensure_connectivity(all_filled, {0, mid}, {cols - 1, mid}, cols, rows)
  end

  # BFS to ensure start and exit are connected. If not, add bridge cells.
  defp ensure_connectivity(cells, start, target, cols, rows) do
    if connected?(cells, start, target) do
      cells
    else
      # Add cells along the middle row to bridge the gap
      mid = div(rows, 2)
      bridge = for col <- 0..(cols - 1), do: {col, mid}
      MapSet.union(cells, MapSet.new(bridge))
    end
  end

  defp connected?(cells, start, target) do
    bfs([start], MapSet.new([start]), cells, target)
  end

  defp bfs([], _visited, _cells, _target), do: false

  defp bfs(queue, visited, cells, target) do
    if target in queue do
      true
    else
      next =
        queue
        |> Enum.flat_map(&grid_neighbors/1)
        |> Enum.filter(&(MapSet.member?(cells, &1) and not MapSet.member?(visited, &1)))
        |> Enum.uniq()

      bfs(next, MapSet.union(visited, MapSet.new(next)), cells, target)
    end
  end

  defp grid_neighbors({col, row}) do
    [{col - 1, row}, {col + 1, row}, {col, row - 1}, {col, row + 1}]
  end

  # Assign zone types respecting adjacency rules
  defp assign_zone_types(cells, cols, rows) do
    cells
    |> Enum.sort()
    |> Enum.reduce(%{}, fn {_col, _row} = pos, acc ->
      # Get already-assigned neighbors
      neighbor_types =
        grid_neighbors(pos)
        |> Enum.filter(&Map.has_key?(acc, &1))
        |> Enum.map(&Map.fetch!(acc, &1))

      type = pick_valid_type(neighbor_types, pos, cols, rows)
      Map.put(acc, pos, type)
    end)
  end

  defp pick_valid_type(neighbor_types, {col, _row}, cols, _rows) do
    # Compute danger estimate for residential adjacency check
    danger_est = danger_base(col, cols)

    candidates =
      @zone_types
      |> Enum.filter(fn type ->
        case type do
          :industrial ->
            # Max 1 adjacent industrial
            Enum.count(neighbor_types, &(&1 == :industrial)) < 1

          :residential ->
            # Not adjacent to danger 6+ (use estimated danger)
            danger_est < 6

          :commercial ->
            # Always allowed (neighbor existence checked at zone level)
            true
        end
      end)

    if candidates == [] do
      Enum.random(@zone_types)
    else
      Enum.random(candidates)
    end
  end

  # Assign danger ratings following a left-to-right gradient
  defp assign_danger_ratings(cells_with_types, cols) do
    Map.new(cells_with_types, fn {{col, row}, type} ->
      danger = compute_danger(col, cols, type)
      {{col, row}, {type, danger}}
    end)
  end

  defp danger_base(col, cols) do
    1 + floor(col * 7 / max(cols - 1, 1))
  end

  defp compute_danger(col, cols, type) do
    base = danger_base(col, cols)
    jitter = Enum.random(-1..1)
    danger = base + jitter

    # Residential zones are capped at danger 5
    max_danger = if type == :residential, do: 5, else: 8

    danger |> max(1) |> min(max_danger)
  end

  # Build Zone structs with neighbor references
  defp build_zones(cells_with_data, _cols, _rows) do
    zone_ids =
      Map.new(cells_with_data, fn {{col, row}, _} ->
        {{col, row}, zone_id(col, row)}
      end)

    Map.new(cells_with_data, fn {{col, row} = pos, {type, danger}} ->
      id = zone_id(col, row)

      neighbors =
        grid_neighbors(pos)
        |> Enum.filter(&Map.has_key?(zone_ids, &1))
        |> Enum.map(&Map.fetch!(zone_ids, &1))

      zone = Zone.new(id, type, danger, pos)
      zone = %{zone | neighbors: neighbors}
      {id, zone}
    end)
  end

  defp zone_id(col, row), do: "zone_#{col}_#{row}"
end
