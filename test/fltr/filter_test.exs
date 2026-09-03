defmodule Fltr.FilterTest do
  use ExUnit.Case, async: true

  import Ecto.Query, only: [dynamic: 2]

  defmodule TeamFilter do
    use Fltr,
      filters: [active: 0, id: 1, name: 1, score_between: 2]

    def parse(:id, id) when is_binary(id) do
      case Integer.parse(id) do
        {id, ""} when id > 0 -> {:ok, id}
        _other -> :error
      end
    end

    def parse(:id, _id), do: :error

    def to_expr(:active), do: dynamic([team], team.active)
    def to_expr(:id, id), do: dynamic([team], team.id == ^id)
    def to_expr(:name, name), do: dynamic([team], team.name == ^name)

    def to_expr(:score_between, minimum, maximum) do
      dynamic([team], team.score >= ^minimum and team.score <= ^maximum)
    end
  end

  defmodule DefaultParserFilter do
    use Fltr, filters: [name: 1]

    def to_expr(:name, name), do: dynamic([team], team.name == ^name)
  end

  defmodule CatchAllParserFilter do
    use Fltr, filters: [name: 1]

    def parse(_name, name), do: {:ok, String.upcase(name)}
    def to_expr(:name, name), do: dynamic([team], team.name == ^name)
  end

  defmodule MalformedParserFilter do
    use Fltr, filters: [range: 2]

    def parse(:range, _range), do: {:ok, :invalid}
    def to_expr(:range, _minimum, _maximum), do: dynamic([], true)
  end

  describe "use Fltr" do
    test "requires a non-empty filters option" do
      assert_raise ArgumentError,
                   "expected :filters to be a non-empty keyword list of names and argument counts",
                   fn -> compile_filter([]) end

      assert_raise ArgumentError,
                   "expected :filters to be a non-empty keyword list of names and argument counts",
                   fn -> compile_filter(filters: []) end
    end

    test "rejects non-keyword and unknown options" do
      assert_raise ArgumentError,
                   "expected options passed to use Fltr to be a keyword list",
                   fn -> compile_filter(:invalid) end

      assert_raise ArgumentError, "unknown Fltr options: [:unknown]", fn ->
        compile_filter(filters: [name: 1], unknown: true)
      end
    end

    test "rejects duplicate and reserved filter names" do
      assert_raise ArgumentError, "filter names must be unique", fn ->
        compile_filter(filters: [name: 1, name: 2])
      end

      for name <- [:all, :any] do
        assert_raise ArgumentError,
                     "#{inspect(name)} is reserved by Fltr",
                     fn ->
                       compile_filter(filters: [{name, 1}])
                     end
      end
    end

    test "rejects invalid argument counts" do
      for count <- [-1, 1.5, :one] do
        assert_raise ArgumentError,
                     "expected the argument count for :name to be a non-negative integer",
                     fn -> compile_filter(filters: [name: count]) end
      end
    end

    test "requires compiler callbacks matching the declared filter arities" do
      assert_raise ArgumentError,
                   ~r/to define compiler callbacks: to_expr\/2/,
                   fn ->
                     compile_filter(filters: [name: 1])
                   end
    end
  end

  describe "parse/1" do
    test "provides parsing when no custom parser is defined" do
      assert DefaultParserFilter.parse(["name", "Rovers"]) ==
               {:ok, {:name, "Rovers"}}
    end

    test "allows a custom parser to handle every filter" do
      assert CatchAllParserFilter.parse(["name", "Rovers"]) ==
               {:ok, {:name, "ROVERS"}}
    end

    test "accepts string and atom filter names in lists and tuples" do
      assert TeamFilter.parse(["name", "Rovers"]) == {:ok, {:name, "Rovers"}}
      assert TeamFilter.parse({:name, "Rovers"}) == {:ok, {:name, "Rovers"}}
      assert TeamFilter.parse({"id", "42"}) == {:ok, {:id, 42}}
    end

    test "preserves the declared filter shape" do
      assert TeamFilter.parse([:active]) == {:ok, {:active}}

      assert TeamFilter.parse([:score_between, 10, 20]) ==
               {:ok, {:score_between, 10, 20}}
    end

    test "uses custom parsers and falls back to passthrough parsing" do
      assert TeamFilter.parse(["id", "42"]) == {:ok, {:id, 42}}
      assert TeamFilter.parse(["name", 42]) == {:ok, {:name, 42}}

      assert TeamFilter.parse(["id", "not-an-id"]) ==
               {:error, {:invalid_arguments, :id, ["not-an-id"]}}

      assert TeamFilter.parse(["id", 42]) ==
               {:error, {:invalid_arguments, :id, [42]}}
    end

    test "rejects parser output that does not preserve a multi-argument shape" do
      assert MalformedParserFilter.parse([:range, 10, 20]) ==
               {:error, {:invalid_arguments, :range, [10, 20]}}
    end

    test "rejects unknown filters" do
      assert TeamFilter.parse(["missing", 1]) ==
               {:error, {:unknown_filter, "missing"}}

      assert TeamFilter.parse({:missing, 1}) ==
               {:error, {:unknown_filter, :missing}}
    end

    test "rejects malformed filters" do
      for filter <- [[], {}, "name", [123, "Rovers"], {123, "Rovers"}] do
        assert TeamFilter.parse(filter) == {:error, {:invalid_filter, filter}}
      end
    end

    test "validates filter argument counts" do
      assert TeamFilter.parse([:name]) ==
               {:error, {:invalid_arguments, :name, []}}

      assert TeamFilter.parse([:active, true]) ==
               {:error, {:invalid_arguments, :active, [true]}}

      assert TeamFilter.parse([:score_between, 10]) ==
               {:error, {:invalid_arguments, :score_between, [10]}}
    end

    test "parses binary boolean groups" do
      assert TeamFilter.parse(["all", [["id", "7"], {:name, "Rovers"}]]) ==
               {:ok, {:all, [{:id, 7}, {:name, "Rovers"}]}}

      assert TeamFilter.parse({:any, [[:active], ["name", "Rovers"]]}) ==
               {:ok, {:any, [{:active}, {:name, "Rovers"}]}}
    end

    test "preserves groups with more than two filters as n-ary lists" do
      assert TeamFilter.parse([
               "any",
               [
                 ["id", "7"],
                 ["name", "Rovers"],
                 ["active"]
               ]
             ]) ==
               {:ok, {:any, [{:id, 7}, {:name, "Rovers"}, {:active}]}}
    end

    test "parses deeply nested boolean groups" do
      assert TeamFilter.parse([
               "all",
               [
                 ["id", "7"],
                 [
                   "any",
                   [
                     ["name", "Rovers"],
                     ["all", [["active"], ["score_between", 10, 20]]]
                   ]
                 ]
               ]
             ]) ==
               {:ok,
                {:all,
                 [
                   {:id, 7},
                   {:any,
                    [
                      {:name, "Rovers"},
                      {:all, [{:active}, {:score_between, 10, 20}]}
                    ]}
                 ]}}
    end

    test "requires boolean groups to receive one non-empty list" do
      assert TeamFilter.parse(["all"]) ==
               {:error, {:invalid_arguments, :all, []}}

      assert TeamFilter.parse([:any, [["name", "Rovers"]]]) ==
               {:ok, {:any, [{:name, "Rovers"}]}}

      assert TeamFilter.parse(["all", []]) ==
               {:error, {:invalid_arguments, :all, []}}

      assert TeamFilter.parse(["any", ["id", "7"], ["active"]]) ==
               {:error, {:invalid_arguments, :any, [["id", "7"], ["active"]]}}
    end

    test "accepts and validates previously parsed expressions" do
      parsed = {:name, "Rovers"}

      assert TeamFilter.parse({:all, [parsed, ["id", "7"]]}) ==
               {:ok, {:all, [parsed, {:id, 7}]}}

      assert TeamFilter.parse({:id, :already_validated}) ==
               {:ok, {:id, :already_validated}}

      assert TeamFilter.parse({:missing, 1}) ==
               {:error, {:unknown_filter, :missing}}

      assert TeamFilter.parse({:score_between, 10}) ==
               {:error, {:invalid_arguments, :score_between, [10]}}
    end
  end

  describe "to_expr/1" do
    test "delegates individual filters to the compiler callback" do
      assert {:ok, id_filter} = TeamFilter.parse(["id", "7"])
      id = 7
      expected_id = dynamic([team], team.id == ^id)

      assert inspect(TeamFilter.to_expr(id_filter)) == inspect(expected_id)

      assert {:ok, score_filter} = TeamFilter.parse([:score_between, 10, 20])
      minimum = 10
      maximum = 20

      expected_score =
        dynamic(
          [team],
          team.score >= ^minimum and team.score <= ^maximum
        )

      assert inspect(TeamFilter.to_expr(score_filter)) ==
               inspect(expected_score)
    end

    test "combines filters with any and all expressions" do
      assert {:ok, filter} =
               TeamFilter.parse([
                 "all",
                 [
                   ["id", "7"],
                   ["any", [["name", "Rovers"], ["active"]]]
                 ]
               ])

      id = 7
      name = "Rovers"

      expected =
        dynamic(
          [team],
          team.id == ^id and (team.name == ^name or team.active)
        )

      assert inspect(TeamFilter.to_expr(filter)) == inspect(expected)
    end

    test "accepts canonical expressions without parsing" do
      filter = {:any, [{:id, 7}, {:name, "Rovers"}, {:active}]}
      id = 7
      name = "Rovers"

      expected =
        dynamic(
          [team],
          team.id == ^id or team.name == ^name or team.active
        )

      assert inspect(TeamFilter.to_expr(filter)) == inspect(expected)
    end

    test "compiles canonical groups containing one filter" do
      expected = dynamic([team], team.active)

      assert inspect(TeamFilter.to_expr({:any, [{:active}]})) ==
               inspect(expected)
    end

    test "rejects empty canonical groups" do
      assert_raise ArgumentError,
                   "expected :any to contain at least one filter, got: []",
                   fn -> TeamFilter.to_expr({:any, []}) end
    end

    test "rejects parsed arguments that do not match the declared arity" do
      assert_raise ArgumentError,
                   "expected 2 arguments for :score_between, got: [:invalid]",
                   fn ->
                     TeamFilter.to_expr({:score_between, :invalid})
                   end
    end
  end

  defp compile_filter(opts) do
    module =
      Module.concat(__MODULE__, "Invalid#{System.unique_integer([:positive])}")

    Code.compile_quoted(
      quote do
        defmodule unquote(module) do
          use Fltr, unquote(opts)
        end
      end
    )
  end
end
