defmodule Fltr do
  @moduledoc """
  Defines reusable filters that compile to Ecto dynamic expressions.

  `use Fltr` turns a module into a filter parser and compiler. The module
  declares the filter names it accepts, validates untrusted input with the
  generated `parse/1`, and converts validated filters with the generated
  `to_expr/1`.

  ## Defining filters

  Declare each filter with the number of arguments it accepts, then implement a
  matching `to_expr` clause:

      defmodule TeamFilter do
        use Fltr, filters: [active: 0, id: 1, name: 1]

        def to_expr(:active), do: dynamic([team], team.active)
        def to_expr(:id, id), do: dynamic([team], team.id == ^id)
        def to_expr(:name, name), do: dynamic([team], team.name == ^name)
      end

  The declared argument count does not include the filter name. In the example,
  `:active` requires `to_expr/1`, while `:id` and `:name` require `to_expr/2`.
  Fltr checks that every required callback arity exists when the module compiles.

  `use Fltr` also imports `Ecto.Query.dynamic/2` into the filter module.

  ## Parsing external input

  String-named lists and tuples are external input. `parse/1` checks their names
  and argument counts, converts names to the declared atoms without creating new
  atoms, and returns a canonical tuple:

      TeamFilter.parse(["id", 7])
      #=> {:ok, {:id, 7}}

  Arguments pass through unchanged by default. Define `parse/2` clauses when a
  filter needs validation or normalization:

      def parse(:id, id) when is_binary(id) do
        case Integer.parse(id) do
          {id, ""} when id > 0 -> {:ok, id}
          _other -> :error
        end
      end

      def parse(:id, _id), do: :error

  For a one-argument filter, `parse/2` receives and returns the argument directly.
  For a filter with two or more arguments, it receives a tuple and must return a
  tuple of the declared size. Filters with no arguments do not invoke `parse/2`.

  Parsed leaves preserve the declared shape: `{:active}`, `{:id, id}`, or
  `{:score_between, minimum, maximum}`.

  Atom-named tuples are considered canonical expressions. Fltr checks their name
  and argument count, but deliberately does not pass their values through
  `parse/2`. Always call `parse/1` on external input before converting it into an
  atom-named tuple.

  ## Boolean groups

  `:all` joins child expressions with `and`; `:any` joins them with `or`. Groups
  require at least one child and may be nested:

      {:any, [{:id, id}, {:active}]}
      {:all, [{:name, name}, {:active}]}

  External groups use the equivalent list form with string names:

      ["any", [["id", id], ["active"]]]

  ## Building a query

  Parse external input, compile the canonical filter, and interpolate the
  resulting dynamic expression into an Ecto query:

      import Ecto.Query

      {:ok, filter} = TeamFilter.parse(["name", "Rovers"])
      filter = TeamFilter.to_expr(filter)

      Team
      |> where(^filter)
      |> Repo.all()
  """

  defmacro __using__(opts) do
    config = Fltr.Config.build(opts)

    quote do
      import Ecto.Query, only: [dynamic: 2]

      @before_compile Fltr
      @fltr_config unquote(Macro.escape(config))

      @typedoc """
      A canonical filter expression accepted by `to_expr/1`.

      This is either a declared filter tuple or a nested `:all`/`:any` group.
      """
      @type t :: Fltr.Filter.t()

      @typedoc "A reason that `parse/1` rejected its input."
      @type parse_error :: Fltr.Filter.parse_error()

      @doc """
      Parses external input or validates a canonical filter expression.

      External leaves use a list or string-named tuple. Their arguments pass
      through the filter module's `parse/2` clauses, or through the generated
      identity parser when no matching clause exists.

      Atom-named tuples are canonical expressions. Their names and argument
      counts are validated, but their values do not pass through `parse/2` again.

      Boolean groups use `:all` or `:any` and contain one non-empty list of child
      expressions. Each child is parsed recursively.

      Returns one of these errors:

        * `{:invalid_filter, input}` when the overall shape is unsupported
        * `{:unknown_filter, name}` when the filter was not declared
        * `{:invalid_arguments, name, arguments}` when the argument count is
          wrong or a custom parser returns `:error` or an invalid shape
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

      @doc """
      Compiles a canonical filter into an Ecto dynamic expression.

      Each leaf is passed to the matching `to_expr` callback defined by the
      filter module. `:all` and `:any` groups are recursively combined with
      `and` and `or`, respectively.

      External input should first be validated with `parse/1`. The returned
      dynamic expression must be interpolated into an Ecto query with `^`.
      """
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
