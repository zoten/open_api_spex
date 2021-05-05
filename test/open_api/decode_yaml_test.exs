defmodule OpenApiSpex.OpenApi.DecodYamlTest do
  use ExUnit.Case
  use Plug.Test

  alias OpenApiSpex.OpenApi

  setup_all do
    spec =
      "./test/support/simple_schema.yaml"
      |> YamlElixir.read_all_from_file!()
      |> List.first()
      |> OpenApiSpex.OpenApi.Decode.decode()

    {:ok, %{spec: spec}}
  end

  describe "Yaml test" do
    test "OpenApi", %{spec: spec} do
      assert %OpenApi{
        openapi: openapi,
        info: _info,
        servers: _servers,
        paths: _paths,
        components: _components,
        security: _security,
        tags: _tags,
        externalDocs: _externalDocs,
        extensions: _extensions
      } = spec

      assert "3.0.0" == openapi
    end

    test "Components", %{spec: spec} do
      assert %OpenApi{
        components: components,
      } = spec

      assert %OpenApiSpex.Components{
        callbacks: _callbacks,
        schemas: schemas,
        responses: _responses,
        examples: _examples,
      } = components

      assert %{
        "AdditionalProperty" => _additional_property,
        "ComplexObject" => complex_object,
        "ExampleObj" => _example,
        "ExampleList" => _example_list
      } = schemas

      assert %OpenApiSpex.Schema{
        type: :object,
        properties: %{
          a_property: %OpenApiSpex.Schema{
            type: :integer
          }
        },
        additionalProperties: %OpenApiSpex.Reference{
          :"$ref" => "#/components/schemas/AdditionalProperty"
        }
      } == complex_object
    end
  end
end
