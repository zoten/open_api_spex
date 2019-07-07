# Open API Spex
[![Build Status](https://travis-ci.com/open-api-spex/open_api_spex.svg?branch=master)](https://travis-ci.com/open-api-spex/open_api_spex)
[![Hex.pm](https://img.shields.io/hexpm/v/open_api_spex.svg)](https://hex.pm/packages/open_api_spex)


Leverage Open Api Specification 3 (swagger) to document, test, validate and explore your Plug and Phoenix APIs.

 - Generate and serve a JSON Open Api Spec document from your code
 - Use the spec to cast request params to well defined schema structs
 - Validate params against schemas, eliminate bad requests before they hit your controllers
 - Validate responses against schemas in tests, ensuring your docs are accurate and reliable
 - Explore the API interactively with with [SwaggerUI](https://swagger.io/swagger-ui/)

Full documentation available on [hexdocs](https://hexdocs.pm/open_api_spex/)

## Installation

The package can be installed by adding `open_api_spex` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:open_api_spex, "~> 3.4"}
  ]
end
```

## Generate Spec

Start by adding an `ApiSpec` module to your application to populate an `OpenApiSpex.OpenApi` struct.

```elixir
defmodule MyAppWeb.ApiSpec do
  alias OpenApiSpex.{OpenApi, Server, Info, Paths}
  alias MyAppWeb.{Endpoint, Router}
  @behaviour OpenApi

  @impl OpenApi
  def spec do
    %OpenApi{
      servers: [
        # Populate the Server info from a phoenix endpoint
        Server.from_endpoint(Endpoint)
      ],
      info: %Info{
        title: "My App",
        version: "1.0"
      },
      # populate the paths from a phoenix router
      paths: Paths.from_router(Router)
    }
    |> OpenApiSpex.resolve_schema_modules() # discover request/response schemas from path specs
  end
end
```

For each plug (controller) that will handle api requests, add an `open_api_operation` callback.
It will be passed the plug opts that were declared in the router, this will be the action for a phoenix controller. The callback populates an `OpenApiSpex.Operation` struct describing the plug/action.

```elixir
defmodule MyAppWeb.UserController do
  alias OpenApiSpex.Operation
  alias MyAppWeb.Schemas.UserResponse

  @spec open_api_operation(atom) :: Operation.t()
  def open_api_operation(action) do
    operation = String.to_existing_atom("#{action}_operation")
    apply(__MODULE__, operation, [])
  end

  @spec show_operation() :: Operation.t()
  def show_operation() do
    %Operation{
      tags: ["users"],
      summary: "Show user",
      description: "Show a user by ID",
      operationId: "UserController.show",
      parameters: [
        Operation.parameter(:id, :path, :integer, "User ID", example: 123, required: true)
      ],
      responses: %{
        200 => Operation.response("User", "application/json", UserResponse)
      }
    }
  end

  # Controller's `show` action
  def show(conn, %{id: id}) do
    {:ok, user} = MyApp.Users.find_by_id(id)
    json(conn, 200, user)
  end

  # For examples of other action operations, see
  # https://github.com/open-api-spex/open_api_spex/blob/master/examples/phoenix_app/lib/phoenix_app_web/controllers/user_controller.ex
end
```

Declare the JSON schemas for request/response bodies in a `Schemas` module:
Each module should implement the `OpenApiSpex.Schema` behaviour.
The only callback is `schema/0`, which should return an `OpenApiSpex.Schema` struct.
You may optionally declare a struct, linked to the JSON schema through the `x-struct` extension property.
See `OpenApiSpex.schema/1` macro for a convenient way to reduce some boilerplate.

```elixir
defmodule MyAppWeb.Schemas do
  alias OpenApiSpex.Schema

  defmodule User do
    OpenApiSpex.schema(%{
      title: "User",
      description: "A user of the app",
      type: :object,
      properties: %{
        id: %Schema{type: :integer, description: "User ID"},
        name: %Schema{type: :string, description: "User name", pattern: ~r/[a-zA-Z][a-zA-Z0-9_]+/},
        email: %Schema{type: :string, description: "Email address", format: :email},
        birthday: %Schema{type: :string, description: "Birth date", format: :date},
        inserted_at: %Schema{
          type: :string,
          description: "Creation timestamp",
          format: :"date-time"
        },
        updated_at: %Schema{type: :string, description: "Update timestamp", format: :"date-time"}
      },
      required: [:name, :email],
      example: %{
        "id" => 123,
        "name" => "Joe User",
        "email" => "joe@gmail.com",
        "birthday" => "1970-01-01T12:34:55Z",
        "inserted_at" => "2017-09-12T12:34:55Z",
        "updated_at" => "2017-09-13T10:11:12Z"
      }
    })
  end

  defmodule UserResponse do
    require OpenApiSpex

    OpenApiSpex.schema(%{
      title: "UserResponse",
      description: "Response schema for single user",
      type: :object,
      properties: %{
        data: User
      },
      example: %{
        "data" => %{
          "id" => 123,
          "name" => "Joe User",
          "email" => "joe@gmail.com",
          "birthday" => "1970-01-01T12:34:55Z",
          "inserted_at" => "2017-09-12T12:34:55Z",
          "updated_at" => "2017-09-13T10:11:12Z"
        }
      }
    })
  end
end
```

For more examples of schema definitions, see the [sample Phoenix app](https://github.com/open-api-spex/open_api_spex/blob/master/examples/phoenix_app/lib/phoenix_app_web/schemas.ex)

Now you can create a mix task to write the swagger file to disk:

```elixir
defmodule Mix.Tasks.MyApp.OpenApiSpec do
  def run([output_file]) do
    json =
      MyAppWeb.ApiSpec.spec()
      |> Jason.encode!(pretty: true)

    :ok = File.write!(output_file, json)
  end
end
```

Generate the file with: `mix myapp.openapispec spec.json`

## Serve Spec

To serve the API spec from your application, first add the `OpenApiSpex.Plug.PutApiSpec` plug somewhere in the pipeline.

```elixir
  pipeline :api do
    plug OpenApiSpex.Plug.PutApiSpec, module: MyAppWeb.ApiSpec
  end
```

Now the spec will be available for use in downstream plugs.
The `OpenApiSpex.Plug.RenderSpec` plug will render the spec as JSON:

```elixir
  scope "/api" do
    pipe_through :api
    resources "/users", MyAppWeb.UserController, only: [:create, :index, :show]
    get "/openapi", OpenApiSpex.Plug.RenderSpec, []
  end
```

## Serve Swagger UI

Once your API spec is available through a route, the `OpenApiSpex.Plug.SwaggerUI` plug can be used to serve a SwaggerUI interface.  The `path:` plug option must be supplied to give the path to the API spec.

All JavaScript and CSS assets are sourced from cdnjs.cloudflare.com, rather than vendoring into this package.

```elixir
  scope "/" do
    pipe_through :browser # Use the default browser stack

    get "/", MyAppWeb.PageController, :index
    get "/swaggerui", OpenApiSpex.Plug.SwaggerUI, path: "/api/openapi"
  end

  scope "/api" do
    pipe_through :api

    resources "/users", MyAppWeb.UserController, only: [:create, :index, :show]
    get "/openapi", OpenApiSpex.Plug.RenderSpec, []
  end
```

## Validating and Casting Params

OpenApiSpex can automatically validate requests before they reach the controller action function. Or if you prefer,
you can explicitly call on OpenApiSpex to cast and validate the params within the controller action. This section
describes the former.

First, the `plug OpenApiSpex.Plug.PutApiSpec` needs to be called in the Router, as described above.

Add the `OpenApiSpex.Plug.CastAndValidate` plug to a controller to validate request parameters, and to cast to Elixir types defined by the operation schema.

```elixir
plug OpenApiSpex.Plug.CastAndValidate
```

The `operation_id` can be inferred when used from a Phoenix controller from the contents of `conn.private`.

```elixir
defmodule MyAppWeb.UserController do
  use MyAppWeb, :controller
  alias OpenApiSpex.Operation
  alias MyAppWeb.Schemas.{User, UserRequest, UserResponse}

  plug OpenApiSpex.Plug.CastAndValidate

  def open_api_operation(action) do
    apply(__MODULE__, :"#{action}_operation", [])
  end

  def create_operation do
    import Operation
    %Operation{
      tags: ["users"],
      summary: "Create user",
      description: "Create a user",
      operationId: "UserController.create",
      parameters: [
        parameter(:id, :query, :integer, "user ID")
      ],
      requestBody: request_body("The user attributes", "application/json", UserRequest),
      responses: %{
        201 => response("User", "application/json", UserResponse)
      }
    }
  end

  def create(conn = %{body_params: %UserRequest{user: %User{name: name, email: email, birthday: birthday = %Date{}}}}, %{id: id}) do
    # conn.body_params cast to UserRequest struct
    # conn.params.id cast to integer
  end
end
```

Now the client will receive a 422 response whenever the request fails to meet the validation rules from the api spec.

The response body will include the validation error message:

```json
{
  "errors": [
    {
      "message": "Invalid format. Expected :date",
      "source": {
        "pointer": "/data/birthday"
      },
      "title": "Invalid value"
    }
  ]
}
```

See also `OpenApiSpex.cast_and_validate/3` and `OpenApiSpex.Cast.cast/3` for more examples outside of a `plug` pipeline.

## Validate Examples

As schemas evolve, you may want to confirm that the examples given match the schemas.
Use the `OpenApiSpex.Test.Assertions` module to assert on schema validations.

```elixir
use ExUnit.Case
import OpenApiSpex.Test.Assertions

test "UsersResponse example matches schema" do
  api_spec = MyAppWeb.ApiSpec.spec()
  schema = MyAppWeb.Schemas.UsersResponse.schema()
  assert_schema(schema.example, "UsersResponse", api_spec)
end
```

## Validate Responses

API responses can be tested against schemas using `OpenApiSpex.Test.Assertions` also:

```elixir
use MyAppWeb.ConnCase
import OpenApiSpex.Test.Assertions

test "UserController produces a UsersResponse", %{conn: conn} do
  api_spec = MyAppWeb.ApiSpec.spec()
  json =
    conn
    |> get(user_path(conn, :index))
    |> json_response(200)

  assert_schema(json, "UsersResponse", api_spec)
end
```
