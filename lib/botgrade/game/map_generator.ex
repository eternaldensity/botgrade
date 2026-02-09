defmodule Botgrade.Game.MapGenerator do
  @moduledoc """
  Procedural generation of branching-path campaign maps.

  Generates a layer-based graph: a start node on the left, several layers
  of branching/merging nodes in the middle, and an exit node on the right.
  """

  alias Botgrade.Game.{MapNode, Zone}

  @viewbox_width 1000
  @viewbox_height 600
  @padding_x 80
  @padding_y 60

  @node_type_weights [combat: 50, shop: 15, rest: 15, event: 20]

  @zone_types [:industrial, :residential, :commercial]

  @enemy_by_danger %{
    1 => [{"rogue", 1.0}],
    2 => [{"rogue", 0.6}, {"strikebolt", 0.4}],
    3 => [{"rogue", 0.2}, {"strikebolt", 0.3}, {"ironclad", 0.3}, {"hexapod", 0.2}],
    4 => [{"strikebolt", 0.25}, {"ironclad", 0.35}, {"hexapod", 0.4}],
    5 => [{"ironclad", 0.4}, {"hexapod", 0.6}]
  }

  @node_labels %{
    combat: ["Hostile Contact", "Enemy Patrol", "Rogue Bot", "Ambush Point", "Danger Zone"],
    shop: ["Scrap Trader", "Parts Dealer", "Salvage Shop", "Component Market"],
    rest: ["Shelter", "Repair Bay", "Safe Zone", "Maintenance Hub"],
    event: ["Signal Source", "Data Cache", "Anomaly", "Unknown Contact", "Wreckage Site"],
    start: ["Entry Point"],
    exit: ["Research Lab"]
  }

  @doc """
  Generate a complete campaign map.

  Options:
    - `:layers` - number of layers including start and exit (default 6)
    - `:min_nodes_per_layer` - minimum nodes in middle layers (default 2)
    - `:max_nodes_per_layer` - maximum nodes in middle layers (default 4)
  """
  @spec generate_map(keyword()) :: %{String.t() => MapNode.t()}
  def generate_map(opts \\ []) do
    layer_count = Keyword.get(opts, :layers, 6)
    min_nodes = Keyword.get(opts, :min_nodes_per_layer, 2)
    max_nodes = Keyword.get(opts, :max_nodes_per_layer, 4)

    zones = generate_zones(layer_count)

    layers =
      0..(layer_count - 1)
      |> Enum.map(fn layer_idx ->
        generate_layer(layer_idx, layer_count, min_nodes, max_nodes, zones)
      end)

    layers_with_edges = connect_layers(layers)

    layers_with_edges
    |> List.flatten()
    |> Map.new(fn node -> {node.id, node} end)
  end

  # Generate zone assignments for each layer
  defp generate_zones(layer_count) do
    # Split layers into 2-3 zone segments
    zone_count = if layer_count <= 4, do: 2, else: 3
    segment_size = ceil(layer_count / zone_count)

    0..(layer_count - 1)
    |> Enum.map(fn layer_idx ->
      zone_idx = min(div(layer_idx, segment_size), zone_count - 1)
      zone_type = Enum.at(@zone_types, rem(zone_idx, length(@zone_types)))
      danger = danger_for_layer(layer_idx, layer_count)
      Zone.new(zone_type, danger)
    end)
  end

  defp danger_for_layer(0, _total), do: 1
  defp danger_for_layer(layer_idx, total) when layer_idx == total - 1, do: 5

  defp danger_for_layer(layer_idx, total) do
    progress = layer_idx / (total - 1)

    cond do
      progress < 0.35 -> Enum.random(1..2)
      progress < 0.7 -> Enum.random(2..3)
      true -> Enum.random(3..4)
    end
  end

  # Generate nodes for a single layer
  defp generate_layer(0, _total, _min, _max, zones) do
    zone = Enum.at(zones, 0)
    pos = {to_float(@padding_x), to_float(@viewbox_height / 2)}

    [
      %MapNode{
        id: "node_0_0",
        type: :start,
        position: pos,
        zone: zone,
        cleared: true,
        label: Enum.random(@node_labels[:start]),
        danger_rating: zone.danger_rating
      }
    ]
  end

  defp generate_layer(layer_idx, total, _min, _max, zones) when layer_idx == total - 1 do
    zone = Enum.at(zones, layer_idx)
    x = to_float(@padding_x + (@viewbox_width - 2 * @padding_x) * layer_idx / (total - 1))
    pos = {x, to_float(@viewbox_height / 2)}

    [
      %MapNode{
        id: "node_#{layer_idx}_0",
        type: :exit,
        position: pos,
        zone: zone,
        label: Enum.random(@node_labels[:exit]),
        enemy_type: weighted_random(@enemy_by_danger[5]),
        danger_rating: zone.danger_rating
      }
    ]
  end

  defp generate_layer(layer_idx, total, min_nodes, max_nodes, zones) do
    zone = Enum.at(zones, layer_idx)
    node_count = Enum.random(min_nodes..max_nodes)
    x = to_float(@padding_x + (@viewbox_width - 2 * @padding_x) * layer_idx / (total - 1))

    0..(node_count - 1)
    |> Enum.map(fn node_idx ->
      y = node_y(node_idx, node_count)
      type = pick_node_type(layer_idx, total)
      danger = zone.danger_rating

      %MapNode{
        id: "node_#{layer_idx}_#{node_idx}",
        type: type,
        position: {x + jitter(15), y + jitter(20)},
        zone: zone,
        label: Enum.random(@node_labels[type]),
        enemy_type: if(type in [:combat, :exit], do: weighted_random(@enemy_by_danger[danger])),
        danger_rating: danger
      }
    end)
    |> enforce_node_constraints(layer_idx, total)
  end

  defp node_y(node_idx, node_count) do
    usable_height = @viewbox_height - 2 * @padding_y

    if node_count == 1 do
      to_float(@viewbox_height / 2)
    else
      spacing = usable_height / (node_count - 1)
      to_float(@padding_y + spacing * node_idx)
    end
  end

  defp jitter(range) do
    to_float(:rand.uniform() * range * 2 - range)
  end

  # Pick a node type using weighted random, with constraints
  defp pick_node_type(_layer_idx, _total) do
    weighted_random_atom(@node_type_weights)
  end

  # Ensure at least one combat node per layer, no shops in first inner layer
  defp enforce_node_constraints(nodes, 1, _total) do
    # First inner layer: no shops, ensure combat presence
    nodes
    |> Enum.map(fn node ->
      if node.type == :shop, do: %{node | type: :combat, label: Enum.random(@node_labels[:combat])}, else: node
    end)
    |> ensure_combat()
  end

  defp enforce_node_constraints(nodes, _layer_idx, _total) do
    ensure_combat(nodes)
  end

  # Make sure at least one node is combat
  defp ensure_combat(nodes) do
    has_combat = Enum.any?(nodes, &(&1.type == :combat))

    if has_combat do
      nodes
    else
      # Convert a random non-special node to combat
      idx = Enum.random(0..(length(nodes) - 1))

      List.update_at(nodes, idx, fn node ->
        danger = node.danger_rating

        %{node |
          type: :combat,
          label: Enum.random(@node_labels[:combat]),
          enemy_type: weighted_random(@enemy_by_danger[danger])
        }
      end)
    end
  end

  # Connect layers with edges (forward direction only)
  defp connect_layers(layers) do
    layers
    |> Enum.with_index()
    |> Enum.map(fn {layer_nodes, layer_idx} ->
      if layer_idx < length(layers) - 1 do
        next_layer = Enum.at(layers, layer_idx + 1)
        add_forward_edges(layer_nodes, next_layer)
      else
        layer_nodes
      end
    end)
    |> ensure_all_reachable()
  end

  # Each node in this layer connects to 1-2 nodes in the next layer
  defp add_forward_edges(current_nodes, next_nodes) do
    next_ids = Enum.map(next_nodes, & &1.id)

    Enum.map(current_nodes, fn node ->
      # Connect to 1-2 random nodes in the next layer
      connect_count = if length(next_ids) == 1, do: 1, else: Enum.random(1..min(2, length(next_ids)))
      targets = Enum.take_random(next_ids, connect_count)
      %{node | edges: Enum.uniq(node.edges ++ targets)}
    end)
  end

  # Ensure every non-start node has at least one incoming edge
  defp ensure_all_reachable(layers) do
    flat = List.flatten(layers)
    all_edges = flat |> Enum.flat_map(fn n -> Enum.map(n.edges, &{n.id, &1}) end)
    nodes_with_incoming = all_edges |> Enum.map(&elem(&1, 1)) |> MapSet.new()

    # For each layer (except first), check each node has an incoming edge
    layers
    |> Enum.with_index()
    |> Enum.reduce(layers, fn {_layer_nodes, layer_idx}, acc ->
      if layer_idx == 0 do
        acc
      else
        current_nodes = Enum.at(acc, layer_idx)
        prev_layer = Enum.at(acc, layer_idx - 1)

        orphans =
          current_nodes
          |> Enum.filter(fn node -> not MapSet.member?(nodes_with_incoming, node.id) end)

        if orphans == [] do
          acc
        else
          # Connect a random node from the previous layer to each orphan
          updated_prev =
            Enum.reduce(orphans, prev_layer, fn orphan, prev ->
              source_idx = Enum.random(0..(length(prev) - 1))

              List.update_at(prev, source_idx, fn source ->
                %{source | edges: Enum.uniq(source.edges ++ [orphan.id])}
              end)
            end)

          List.replace_at(acc, layer_idx - 1, updated_prev)
        end
      end
    end)
  end

  # Weighted random selection returning the item (for enemy types)
  defp weighted_random(weighted_list) do
    total = weighted_list |> Enum.map(&elem(&1, 1)) |> Enum.sum()
    roll = :rand.uniform() * total

    weighted_list
    |> Enum.reduce_while(0.0, fn {item, weight}, acc ->
      new_acc = acc + weight
      if new_acc >= roll, do: {:halt, item}, else: {:cont, new_acc}
    end)
  end

  # Weighted random for atom keyword list
  defp weighted_random_atom(weights) do
    total = weights |> Enum.map(&elem(&1, 1)) |> Enum.sum()
    roll = :rand.uniform() * total

    weights
    |> Enum.reduce_while(0, fn {type, weight}, acc ->
      new_acc = acc + weight
      if new_acc >= roll, do: {:halt, type}, else: {:cont, new_acc}
    end)
  end

  defp to_float(n) when is_float(n), do: n
  defp to_float(n), do: n / 1
end
