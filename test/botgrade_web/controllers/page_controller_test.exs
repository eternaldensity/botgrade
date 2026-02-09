defmodule BotgradeWeb.PageControllerTest do
  use BotgradeWeb.ConnCase

  test "GET /", %{conn: conn} do
    conn = get(conn, ~p"/")
    assert html_response(conn, 200) =~ "BOTGRADE"
  end

  test "GET / shows enemy type selector", %{conn: conn} do
    conn = get(conn, ~p"/")
    response = html_response(conn, 200)
    assert response =~ "Ironclad"
    assert response =~ "Strikebolt"
    assert response =~ "Hexapod"
  end

  test "POST /combat/start with enemy_type redirects to combat", %{conn: conn} do
    conn = post(conn, ~p"/combat/start", %{"enemy_type" => "ironclad"})
    assert redirected_to(conn) =~ "/combat/"
  end

  test "POST /combat/start without enemy_type uses default", %{conn: conn} do
    conn = post(conn, ~p"/combat/start", %{})
    assert redirected_to(conn) =~ "/combat/"
  end
end
