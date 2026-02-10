defmodule Botgrade.Game.CardSerializer do
  @moduledoc """
  Serializes and deserializes game structs to/from JSON-safe maps.
  Handles atom keys/values, tuple conditions, and nested structures.
  """

  alias Botgrade.Game.{Card, CampaignState, Space, Tile, Zone}

  # --- Card ---

  def serialize_card(%Card{} = card) do
    %{
      "id" => card.id,
      "name" => card.name,
      "type" => to_string(card.type),
      "damage" => to_string(card.damage),
      "properties" => serialize_properties(card.properties),
      "dice_slots" => Enum.map(card.dice_slots, &serialize_dice_slot/1),
      "current_hp" => card.current_hp
    }
  end

  def deserialize_card(map) do
    %Card{
      id: map["id"],
      name: map["name"],
      type: String.to_atom(map["type"]),
      damage: String.to_atom(map["damage"]),
      properties: deserialize_properties(map["properties"]),
      dice_slots: Enum.map(map["dice_slots"] || [], &deserialize_dice_slot/1),
      current_hp: map["current_hp"]
    }
  end

  # --- Properties (map with atom keys, may contain atom values) ---

  defp serialize_properties(props) do
    Map.new(props, fn {k, v} -> {to_string(k), serialize_prop_value(k, v)} end)
  end

  defp serialize_prop_value(:damage_type, v), do: to_string(v)
  defp serialize_prop_value(:armor_type, v), do: to_string(v)
  defp serialize_prop_value(:activated_this_turn, v), do: v

  defp serialize_prop_value(:targeting_profile, nil), do: nil

  defp serialize_prop_value(:targeting_profile, profile) do
    Map.new(profile, fn {k, v} -> {to_string(k), v} end)
  end

  defp serialize_prop_value(:dual_mode, nil), do: nil

  defp serialize_prop_value(:dual_mode, dm) do
    %{
      "condition" => serialize_condition(dm.condition),
      "armor_type" => to_string(dm.armor_type),
      "shield_base" => dm.shield_base
    }
  end

  defp serialize_prop_value(:element, v), do: to_string(v)
  defp serialize_prop_value(:end_of_turn_effect, v), do: to_string(v)
  defp serialize_prop_value(:utility_ability, v), do: to_string(v)

  defp serialize_prop_value(:cpu_ability, nil), do: nil

  defp serialize_prop_value(:cpu_ability, ability) do
    %{
      "type" => to_string(ability.type),
      "discard_count" => ability[:discard_count],
      "draw_count" => ability[:draw_count],
      "requires_card_name" => ability[:requires_card_name]
    }
  end

  defp serialize_prop_value(_key, v), do: v

  defp deserialize_properties(nil), do: %{}

  defp deserialize_properties(props) do
    Map.new(props, fn {k, v} -> {String.to_atom(k), deserialize_prop_value(k, v)} end)
  end

  defp deserialize_prop_value("damage_type", v), do: String.to_atom(v)
  defp deserialize_prop_value("armor_type", v), do: String.to_atom(v)
  defp deserialize_prop_value("activated_this_turn", v), do: v

  defp deserialize_prop_value("targeting_profile", nil), do: nil

  defp deserialize_prop_value("targeting_profile", profile) do
    Map.new(profile, fn {k, v} -> {String.to_atom(k), v} end)
  end

  defp deserialize_prop_value("dual_mode", nil), do: nil

  defp deserialize_prop_value("dual_mode", dm) do
    %{
      condition: deserialize_condition(dm["condition"]),
      armor_type: String.to_atom(dm["armor_type"]),
      shield_base: dm["shield_base"]
    }
  end

  defp deserialize_prop_value("element", v), do: String.to_atom(v)
  defp deserialize_prop_value("end_of_turn_effect", v), do: String.to_atom(v)
  defp deserialize_prop_value("utility_ability", v), do: String.to_atom(v)

  defp deserialize_prop_value("cpu_ability", nil), do: nil

  defp deserialize_prop_value("cpu_ability", ability) do
    base = %{
      type: String.to_atom(ability["type"]),
      discard_count: ability["discard_count"],
      draw_count: ability["draw_count"]
    }

    if ability["requires_card_name"],
      do: Map.put(base, :requires_card_name, ability["requires_card_name"]),
      else: base
  end

  defp deserialize_prop_value(_key, v), do: v

  # --- Dice Slots ---

  defp serialize_dice_slot(slot) do
    base = %{
      "id" => slot.id,
      "condition" => serialize_condition(slot.condition),
      "assigned_die" => serialize_die(slot.assigned_die)
    }

    if Map.get(slot, :locked), do: Map.put(base, "locked", true), else: base
  end

  defp deserialize_dice_slot(slot) do
    base = %{
      id: slot["id"],
      condition: deserialize_condition(slot["condition"]),
      assigned_die: deserialize_die(slot["assigned_die"])
    }

    if slot["locked"], do: Map.put(base, :locked, true), else: base
  end

  # --- Dice Conditions ---

  defp serialize_condition(nil), do: nil
  defp serialize_condition(:even), do: "even"
  defp serialize_condition(:odd), do: "odd"
  defp serialize_condition({tag, n}), do: [to_string(tag), n]

  defp deserialize_condition(nil), do: nil
  defp deserialize_condition("even"), do: :even
  defp deserialize_condition("odd"), do: :odd
  defp deserialize_condition([tag, n]), do: {String.to_atom(tag), n}

  # --- Dice ---

  defp serialize_die(nil), do: nil

  defp serialize_die(die) do
    %{"sides" => die.sides, "value" => die.value}
    |> maybe_put("blazing", Map.get(die, :blazing))
    |> maybe_put("hidden", Map.get(die, :hidden))
  end

  defp deserialize_die(nil), do: nil

  defp deserialize_die(die) do
    %{sides: die["sides"], value: die["value"]}
    |> maybe_put_atom(:blazing, die["blazing"])
    |> maybe_put_atom(:hidden, die["hidden"])
  end

  # --- Resources ---

  def serialize_resources(resources) do
    Map.new(resources, fn {k, v} -> {to_string(k), v} end)
  end

  def deserialize_resources(nil), do: %{}

  def deserialize_resources(resources) do
    Map.new(resources, fn {k, v} -> {String.to_atom(k), v} end)
  end

  # --- Space ---

  def serialize_space(%Space{} = space) do
    {x, y} = space.position

    %{
      "id" => space.id,
      "type" => to_string(space.type),
      "position" => [x, y],
      "zone_id" => space.zone_id,
      "connections" => space.connections,
      "label" => space.label,
      "enemy_type" => space.enemy_type,
      "enemy_behavior" => if(space.enemy_behavior, do: to_string(space.enemy_behavior)),
      "enemy_patrol_path" => space.enemy_patrol_path,
      "encounter_range" => space.encounter_range,
      "danger_rating" => space.danger_rating,
      "cleared" => space.cleared,
      "access_level" => space.access_level,
      "holds_access_card" => space.holds_access_card
    }
  end

  def deserialize_space(map) do
    [x, y] = map["position"]

    %Space{
      id: map["id"],
      type: String.to_atom(map["type"]),
      position: {x, y},
      zone_id: map["zone_id"],
      connections: map["connections"] || [],
      label: map["label"] || "",
      enemy_type: map["enemy_type"],
      enemy_behavior: if(map["enemy_behavior"], do: String.to_atom(map["enemy_behavior"])),
      enemy_patrol_path: map["enemy_patrol_path"] || [],
      encounter_range: map["encounter_range"] || 1,
      danger_rating: map["danger_rating"] || 1,
      cleared: map["cleared"] || false,
      access_level: map["access_level"],
      holds_access_card: map["holds_access_card"]
    }
  end

  # --- Tile ---

  def serialize_tile(%Tile{} = tile) do
    {x, y, w, h} = tile.bounds

    %{
      "id" => tile.id,
      "zone_id" => tile.zone_id,
      "spaces" => Map.new(tile.spaces, fn {k, v} -> {k, serialize_space(v)} end),
      "edge_connectors" => Map.new(tile.edge_connectors, fn {k, v} -> {to_string(k), v} end),
      "bounds" => [x, y, w, h]
    }
  end

  def deserialize_tile(map) do
    [x, y, w, h] = map["bounds"]

    %Tile{
      id: map["id"],
      zone_id: map["zone_id"],
      spaces: Map.new(map["spaces"], fn {k, v} -> {k, deserialize_space(v)} end),
      edge_connectors:
        Map.new(map["edge_connectors"], fn {k, v} -> {String.to_atom(k), v} end),
      bounds: {x, y, w, h}
    }
  end

  # --- Zone ---

  def serialize_zone(%Zone{} = zone) do
    base = %{
      "type" => to_string(zone.type),
      "danger_rating" => zone.danger_rating,
      "name" => zone.name
    }

    base
    |> maybe_put("id", zone.id)
    |> maybe_put("grid_pos", if(zone.grid_pos, do: Tuple.to_list(zone.grid_pos)))
    |> maybe_put("neighbors", if(zone.neighbors != [], do: zone.neighbors))
  end

  def deserialize_zone(map) do
    base = %Zone{
      type: String.to_atom(map["type"]),
      danger_rating: map["danger_rating"],
      name: map["name"]
    }

    base
    |> then(fn z -> if map["id"], do: %{z | id: map["id"]}, else: z end)
    |> then(fn z ->
      if map["grid_pos"],
        do: %{z | grid_pos: List.to_tuple(map["grid_pos"])},
        else: z
    end)
    |> then(fn z -> if map["neighbors"], do: %{z | neighbors: map["neighbors"]}, else: z end)
  end

  # --- CampaignState ---

  def serialize_campaign(%CampaignState{} = state) do
    %{
      "id" => state.id,
      "seed" => state.seed,
      "zones" => Map.new(state.zones, fn {k, v} -> {k, serialize_zone(v)} end),
      "tiles" => Map.new(state.tiles, fn {k, v} -> {k, serialize_tile(v)} end),
      "spaces" => Map.new(state.spaces, fn {k, v} -> {k, serialize_space(v)} end),
      "current_space_id" => state.current_space_id,
      "player_cards" => Enum.map(state.player_cards, &serialize_card/1),
      "player_resources" => serialize_resources(state.player_resources),
      "visited_spaces" => state.visited_spaces,
      "combat_id" => state.combat_id,
      "movement_points" => state.movement_points,
      "max_movement_points" => state.max_movement_points,
      "turn_number" => state.turn_number,
      "access_cards" => state.access_cards,
      "created_at" => state.created_at,
      "updated_at" => state.updated_at
    }
  end

  def deserialize_campaign(map) do
    # Detect old-format saves (node-based)
    if Map.has_key?(map, "nodes") and not Map.has_key?(map, "zones") do
      {:error, :incompatible_save}
    else
      {:ok,
       %CampaignState{
         id: map["id"],
         seed: map["seed"],
         zones: Map.new(map["zones"], fn {k, v} -> {k, deserialize_zone(v)} end),
         tiles: Map.new(map["tiles"], fn {k, v} -> {k, deserialize_tile(v)} end),
         spaces: Map.new(map["spaces"], fn {k, v} -> {k, deserialize_space(v)} end),
         current_space_id: map["current_space_id"],
         player_cards: Enum.map(map["player_cards"], &deserialize_card/1),
         player_resources: deserialize_resources(map["player_resources"]),
         visited_spaces: map["visited_spaces"] || [],
         combat_id: map["combat_id"],
         movement_points: map["movement_points"] || 1,
         max_movement_points: map["max_movement_points"] || 1,
         turn_number: map["turn_number"] || 1,
         access_cards: map["access_cards"] || [],
         created_at: map["created_at"],
         updated_at: map["updated_at"]
       }}
    end
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  defp maybe_put_atom(map, _key, nil), do: map
  defp maybe_put_atom(map, key, value), do: Map.put(map, key, value)
end
