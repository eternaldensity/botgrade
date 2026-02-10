defmodule Botgrade.Game.CardSerializer do
  @moduledoc """
  Serializes and deserializes game structs to/from JSON-safe maps.
  Handles atom keys/values, tuple conditions, and nested structures.
  """

  alias Botgrade.Game.{Card, CampaignState, MapNode, Zone}

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
    %{
      "id" => slot.id,
      "condition" => serialize_condition(slot.condition),
      "assigned_die" => serialize_die(slot.assigned_die)
    }
  end

  defp deserialize_dice_slot(slot) do
    %{
      id: slot["id"],
      condition: deserialize_condition(slot["condition"]),
      assigned_die: deserialize_die(slot["assigned_die"])
    }
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
  defp serialize_die(die), do: %{"sides" => die.sides, "value" => die.value}

  defp deserialize_die(nil), do: nil
  defp deserialize_die(die), do: %{sides: die["sides"], value: die["value"]}

  # --- Resources ---

  def serialize_resources(resources) do
    Map.new(resources, fn {k, v} -> {to_string(k), v} end)
  end

  def deserialize_resources(nil), do: %{}

  def deserialize_resources(resources) do
    Map.new(resources, fn {k, v} -> {String.to_atom(k), v} end)
  end

  # --- Zone ---

  def serialize_zone(%Zone{} = zone) do
    %{
      "type" => to_string(zone.type),
      "danger_rating" => zone.danger_rating,
      "name" => zone.name
    }
  end

  def deserialize_zone(map) do
    %Zone{
      type: String.to_atom(map["type"]),
      danger_rating: map["danger_rating"],
      name: map["name"]
    }
  end

  # --- MapNode ---

  def serialize_node(%MapNode{} = node) do
    {x, y} = node.position

    %{
      "id" => node.id,
      "type" => to_string(node.type),
      "position" => [x, y],
      "zone" => serialize_zone(node.zone),
      "cleared" => node.cleared,
      "edges" => node.edges,
      "label" => node.label,
      "enemy_type" => node.enemy_type,
      "danger_rating" => node.danger_rating
    }
  end

  def deserialize_node(map) do
    [x, y] = map["position"]

    %MapNode{
      id: map["id"],
      type: String.to_atom(map["type"]),
      position: {x, y},
      zone: deserialize_zone(map["zone"]),
      cleared: map["cleared"],
      edges: map["edges"] || [],
      label: map["label"] || "",
      enemy_type: map["enemy_type"],
      danger_rating: map["danger_rating"] || 1
    }
  end

  # --- CampaignState ---

  def serialize_campaign(%CampaignState{} = state) do
    %{
      "id" => state.id,
      "nodes" => Map.new(state.nodes, fn {k, v} -> {k, serialize_node(v)} end),
      "current_node_id" => state.current_node_id,
      "player_cards" => Enum.map(state.player_cards, &serialize_card/1),
      "player_resources" => serialize_resources(state.player_resources),
      "visited_nodes" => state.visited_nodes,
      "combat_id" => state.combat_id,
      "created_at" => state.created_at,
      "updated_at" => state.updated_at
    }
  end

  def deserialize_campaign(map) do
    %CampaignState{
      id: map["id"],
      nodes: Map.new(map["nodes"], fn {k, v} -> {k, deserialize_node(v)} end),
      current_node_id: map["current_node_id"],
      player_cards: Enum.map(map["player_cards"], &deserialize_card/1),
      player_resources: deserialize_resources(map["player_resources"]),
      visited_nodes: map["visited_nodes"] || [],
      combat_id: map["combat_id"],
      created_at: map["created_at"],
      updated_at: map["updated_at"]
    }
  end
end
