defmodule CaseoWeb.PropertyGalleryTest do
  use CaseoWeb.ConnCase, async: true

  import Caseo.AccountsFixtures
  import Phoenix.LiveViewTest

  alias Caseo.Properties
  alias Caseo.Properties.Photos

  @png Base.decode64!(
         "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jP1sAAAAASUVORK5CYII="
       )

  test "stores separate galleries and protects direct reads and writes", %{conn: conn} do
    owner = user_scope_fixture()
    other = user_scope_fixture()
    property = property_with_room(owner)
    other_property = property_with_room(other)
    assert [room] = property.rooms
    assert [other_room] = other_property.rooms
    owner_conn = log_in_user(conn, owner.user)
    other_conn = log_in_user(build_conn(), other.user)

    {:ok, view, _html} =
      live(owner_conn, ~p"/inmuebles/#{property.id}/habitaciones/#{room.id}/fotos")

    file =
      file_input(view, "#property-photo-form", :photo, [
        %{name: "habitacion.png", content: @png, type: "image/png"}
      ])

    render_upload(file, "habitacion.png")
    view |> form("#property-photo-form") |> render_submit()

    assert [room_photo] = Photos.list(owner, property.id, room.id)
    assert room_photo.cover
    assert has_element?(view, "#property-photos img")

    assert {:ok, common_photo} = Photos.add(owner, property.id, nil, @png)
    assert {:ok, second_photo} = Photos.add(owner, property.id, nil, @png)
    assert {:ok, :saved} = Photos.set_cover(owner, property.id, nil, second_photo.id)
    assert [%{id: cover, cover: true}, %{cover: false}] = Photos.list(owner, property.id, nil)
    assert cover == second_photo.id
    assert {:ok, :deleted} = Photos.delete(owner, property.id, nil, common_photo.id)
    assert {:error, :invalid_image} = Photos.add(owner, property.id, nil, "<svg></svg>")
    assert {:error, :not_found} = Photos.add(owner, property.id, other_room.id, @png)

    image_path = ~p"/archivos/inmuebles/#{room_photo.id}"

    response =
      owner_conn
      |> put_req_header("accept", "image/avif,image/webp,image/apng,image/*,*/*;q=0.8")
      |> get(image_path)

    assert response(response, 200) == @png
    assert get_resp_header(response, "content-type") == ["image/png"]
    assert get_resp_header(response, "cache-control") == ["private, no-store"]
    assert response(get(other_conn, image_path), 404) == ""
    assert redirected_to(get(build_conn(), image_path)) == ~p"/users/log-in"

    assert {:error, {:redirect, %{to: path}}} = live(other_conn, ~p"/inmuebles/#{property.id}")
    assert path == ~p"/inmuebles"

    assert {:error, {:redirect, %{to: path}}} =
             live(other_conn, ~p"/inmuebles/#{other_property.id}/habitaciones/#{room.id}/fotos")

    assert path == ~p"/inmuebles"
    assert {:error, :not_found} = Photos.delete(other, property.id, room.id, room_photo.id)
    assert {:error, :not_found} = Photos.set_cover(other, property.id, nil, second_photo.id)
    assert {:error, :not_found} = Photos.set_cover(owner, property.id, nil, room_photo.id)

    assert :ok = Properties.archive_property(owner, property.id)
    assert Properties.list_properties(owner) == []
    assert [%{rooms: [%{id: room_id}]}] = Properties.list_properties(owner, :archived)
    assert room_id == room.id
    assert [%{id: id}] = Photos.list(owner, property.id, room.id)
    assert id == room_photo.id
  end

  defp property_with_room(scope) do
    {:ok, property} =
      Properties.create_property(scope, %{
        "name" => "Piso centro",
        "mode" => "rooms",
        "street" => "Calle Mayor 12",
        "municipality" => "Madrid",
        "postal_code" => "28013",
        "province" => "Madrid",
        "rooms" => [%{"name" => "Habitación sur", "rent" => "450"}]
      })

    property
  end
end
