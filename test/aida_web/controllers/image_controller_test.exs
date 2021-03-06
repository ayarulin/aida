defmodule AidaWeb.ImageControllerTest do
  use AidaWeb.ConnCase
  alias Aida.DB

  test "gets image", %{conn: conn} do
    image_attrs = %{
      binary: "an image",
      binary_type: "image/jpeg",
      source_url: "http://www.foo.bar/?gfe_rd=cr&dcr=0&ei=5x9ZWpjLOY3j8Af5t7OIAw",
      bot_id: "e75ecc4a-b8b6-421f-a40d-6c72a13d910c",
      session_id: "e75ecc4a-b8b6-421f-a40d-6c72a13d910c/facebook/388255354930539/1216983898405257"
    }

    DB.create_image(image_attrs)
    image_uuid = (Aida.DB.Image |> Aida.Repo.one).uuid
    conn = get conn, image_path(conn, :image, image_uuid)
    assert response(conn, 200) == "an image"
  end

  test "gets 404 when image is not found", %{conn: conn} do
    conn = get conn, image_path(conn, :image, "e75ecc4a-b8b6-421f-a40d-6c72a13d910c")
    assert response(conn, 404)
  end

end
