defmodule Fltr do
  @moduledoc """
  Defines reusable parsing and Ecto expression composition for filters.

  A filter module declares its supported names and argument counts and implements
  `to_expr` clauses that match those declarations:

      defmodule TeamFilter do
        use Fltr, filters: [active: 0, id: 1, name: 1]

        def to_expr(:active), do: dynamic([team], team.active)
        def to_expr(:id, id), do: dynamic([team], team.id == ^id)
        def to_expr(:name, name), do: dynamic([team], team.name == ^name)
      end

  Parsing is optional. Declared filters pass their input through unchanged unless
  the filter module implements `parse/2` for names that need validation or
  normalization. Unary filters receive their argument directly, filters with
  multiple arguments receive a tuple, and filters without arguments require no
  parsing.

  Parsed leaves preserve the declared shape: `{:active}`, `{:id, id}`, or
  `{:score_between, minimum, maximum}`.

  Lists and string-named tuples are treated as external input, so their arguments
  pass through `parse/2`. Atom-named tuples are trusted canonical expressions:
  their argument count is checked, but their values are not parsed again.

  Boolean groups contain a non-empty list of child expressions:

      {:any, [{:id, id}, {:active}]}
      {:all, [{:name, name}, {:active}]}

  External groups use the equivalent list form with string names:

      ["any", [["id", id], ["active"]]]

  Parse external input, compile it, and interpolate the resulting dynamic
  expression into an Ecto query:

      import Ecto.Query

      {:ok, filter} = TeamFilter.parse(["name", "Rovers"])
      filter = TeamFilter.to_expr(filter)

      Team
      |> where(^filter)
      |> Repo.all()

  `use Fltr` supplies the public `parse/1` and `to_expr/1` functions, imports
  `Ecto.Query.dynamic/2`, and validates the required `to_expr` arities when the
  filter module is compiled.
  """

  defmacro __using__(opts) do
    config = Fltr.Config.build(opts)

    quote do
      import Ecto.Query, only: [dynamic: 2]

      @before_compile Fltr
      @fltr_config unquote(Macro.escape(config))

      @typedoc "A validated filter expression returned by `parse/1`."
      @type t :: Fltr.Filter.t()

      @type parse_error :: Fltr.Filter.parse_error()

      @doc """
      Parses external input or validates a canonical filter expression.

      Atom-named tuples are treated as canonical expressions, so their values do
      not pass through `parse/2` again.
      """
      @spec parse(term()) :: {:ok, t()} | {:error, parse_error()}
      def parse(input) do
        Fltr.Filter.parse(input, @fltr_config, &parse/2)
      end
    end
  end

  defmacro __before_compile__(env) do
    config = Module.get_attribute(env.module, :fltr_config)
    validate_compiler_arities!(env.module, config)

    quote generated: true do
      @doc false
      def parse(_name, input), do: {:ok, input}

      @doc "Compiles a validated filter into an Ecto dynamic expression."
      @spec to_expr(t()) :: Ecto.Query.dynamic_expr()
      def to_expr(filter) when is_tuple(filter) and tuple_size(filter) > 0 do
        Fltr.Expr.from_filter(filter, {@fltr_config, __MODULE__})
      end
    end
  end

  defp validate_compiler_arities!(module, {arities, _names}) do
    missing_arities =
      arities
      |> Map.values()
      |> Enum.map(&(&1 + 1))
      |> Enum.uniq()
      |> Enum.sort()
      |> Enum.reject(&Module.defines?(module, {:to_expr, &1}, :def))

    if missing_arities != [] do
      callbacks = Enum.map_join(missing_arities, ", ", &"to_expr/#{&1}")

      raise ArgumentError,
            "expected #{inspect(module)} to define compiler callbacks: #{callbacks}"
    end
  end
end
