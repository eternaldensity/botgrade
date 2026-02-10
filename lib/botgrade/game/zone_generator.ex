defmodule Botgrade.Game.ZoneGenerator do
  @moduledoc """
  Generates a grid of zones for the campaign map from a seed.
  Produces an 8x5 grid with ~60% fill, maze-like connectivity,
  and a danger gradient from start (left) to exit (right).
  """

  alias Botgrade.Game.Zone

  @zone_types [:industrial, :residential, :commercial]
  @grid_cols 8
  @grid_rows 5

  @doc """
  Generate a zone grid from a seed. Returns `%{zone_id => Zone.t()}`.

  Options:
    - `:grid_cols` - grid width (default 8)
    - `:grid_rows` - grid height (default 5)
  """
  @spec generate_zones(integer(), keyword()) :: %{String.t() => Zone.t()}
  def generate_zones(seed, opts \\ []) do
    cols = Keyword.get(opts, :grid_cols, @grid_cols)
    rows = Keyword.get(opts, :grid_rows, @grid_rows)

    # Seed the RNG deterministically
    :rand.seed(:exsss, {seed, seed + 1, seed + 2})

    # Step 1: Determine which grid cells are filled
    cells = generate_cell_layout(cols, rows)

    # Step 2: Generate maze-like connectivity (spanning tree + some extras)
    edges = generate_maze_edges(cells)

    # Step 3: Assign zone types respecting adjacency rules
    cells_with_types = assign_zone_types(cells, cols, rows)

    # Step 4: Assign danger ratings with gradient
    cells_with_danger = assign_danger_ratings(cells_with_types, cols)

    # Step 5: Build Zone structs with maze neighbor lists
    build_zones(cells_with_danger, edges)
  end

  # Generate which cells are filled. Start and exit are always filled.
  # Fills ~60% of remaining cells, ensuring connectivity.
  defp generate_cell_layout(cols, rows) do
    # Always fill start {0, mid} and exit {cols-1, mid}
    mid = div(rows, 2)
    required = [{0, mid}, {cols - 1, mid}]

    # Generate candidate cells (all positions except required)
    all_cells =
      for col <- 0..(cols - 1), row <- 0..(rows - 1), {col, row} not in required, do: {col, row}

    # Fill ~60% of remaining cells for more gaps
    fill_count = round(length(all_cells) * 0.60)
    filled = Enum.take_random(all_cells, fill_count)
    all_filled = MapSet.new(required ++ filled)

    # Ensure path connectivity from start to exit using BFS
    ensure_connectivity(all_filled, {0, mid}, {cols - 1, mid}, cols, rows)
  end

  # BFS to ensure start and exit are connected. If not, add bridge cells.
  # Then prune any cells not reachable from start to eliminate islands.
  defp ensure_connectivity(cells, start, target, cols, rows) do
    connected_cells =
      if connected?(cells, start, target) do
        cells
      else
        mid = div(rows, 2)
        bridge = for col <- 0..(cols - 1), do: {col, mid}
        MapSet.union(cells, MapSet.new(bridge))
      end

    # Flood-fill from start and keep only reachable cells
    reachable = flood_fill(connected_cells, start)
    MapSet.intersection(connected_cells, reachable)
  end

  defp connected?(cells, start, target) do
    reachable = flood_fill(cells, start)
    MapSet.member?(reachable, target)
  end

  defp flood_fill(cells, start) do
    do_flood([start], MapSet.new([start]), cells)
  end

  defp do_flood([], visited, _cells), do: visited

  defp do_flood(queue, visited, cells) do
    next =
      queue
      |> Enum.flat_map(&grid_neighbors/1)
      |> Enum.filter(&(MapSet.member?(cells, &1) and not MapSet.member?(visited, &1)))
      |> Enum.uniq()

    do_flood(next, MapSet.union(visited, MapSet.new(next)), cells)
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

  # Generate maze-like edges: random spanning tree + ~25% extra edges for loops.
  # Returns a MapSet of edges as sorted tuples {pos_a, pos_b} where pos_a < pos_b.
  defp generate_maze_edges(cells) do
    cell_list = MapSet.to_list(cells)

    # All possible edges between adjacent filled cells
    all_edges =
      for a <- cell_list,
          b <- grid_neighbors(a),
          MapSet.member?(cells, b),
          a < b,
          do: {a, b}

    all_edges = Enum.uniq(all_edges)

    # Build spanning tree using randomized Kruskal's algorithm
    shuffled = Enum.shuffle(all_edges)
    parent = Map.new(cell_list, fn c -> {c, c} end)

    {tree_edges, _parent} =
      Enum.reduce(shuffled, {[], parent}, fn {a, b}, {edges, par} ->
        ra = find_root(par, a)
        rb = find_root(par, b)

        if ra != rb do
          {[{a, b} | edges], Map.put(par, ra, rb)}
        else
          {edges, par}
        end
      end)

    tree_set = MapSet.new(tree_edges)

    # Add ~25% of remaining edges for occasional loops
    extra_candidates = Enum.filter(all_edges, fn e -> not MapSet.member?(tree_set, e) end)
    extra_count = round(length(extra_candidates) * 0.25)
    extra = Enum.take_random(extra_candidates, extra_count)

    MapSet.union(tree_set, MapSet.new(extra))
  end

  defp find_root(parent, node) do
    case Map.fetch!(parent, node) do
      ^node -> node
      p -> find_root(parent, p)
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

  # Build Zone structs with maze-derived neighbor references
  defp build_zones(cells_with_data, edges) do
    zone_ids =
      Map.new(cells_with_data, fn {{col, row}, _} ->
        {{col, row}, zone_id(col, row)}
      end)

    Map.new(cells_with_data, fn {{col, row} = pos, {type, danger}} ->
      id = zone_id(col, row)

      # Only include neighbors connected by maze edges
      neighbors =
        grid_neighbors(pos)
        |> Enum.filter(fn nb ->
          Map.has_key?(zone_ids, nb) and
            (MapSet.member?(edges, {min(pos, nb), max(pos, nb)}))
        end)
        |> Enum.map(&Map.fetch!(zone_ids, &1))

      zone = Zone.new(id, type, danger, pos)
      zone = %{zone | neighbors: neighbors}
      {id, zone}
    end)
  end

  defp zone_id(col, row), do: "zone_#{col}_#{row}"
end
