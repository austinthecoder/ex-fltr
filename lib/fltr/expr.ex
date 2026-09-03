defmodule Fltr.Expr do
  @moduledoc false

  import Ecto.Query, only: [dynamic: 2]

  @group_operators [:any, :all]

  @spec from_filter(tuple(), {Fltr.Config.t(), module()}) ::
          Ecto.Query.dynamic_expr()
  def from_filter({operator, [filter]}, context)
      when operator in @group_operators do
    from_filter(filter, context)
  end

  def from_filter({operator, [left, right]}, context)
      when operator in @group_operators do
    left_expr = from_filter(left, context)
    right_expr = from_filter(right, context)

    case operator do
      :any -> dynamic([], ^left_expr or ^right_expr)
      :all -> dynamic([], ^left_expr and ^right_expr)
    end
  end

  def from_filter({operator, [left, right, next | filters]}, context)
      when operator in @group_operators do
    pair = {operator, [left, right]}
    from_filter({operator, [pair, next | filters]}, context)
  end

  def from_filter({operator, filters}, _context)
      when operator in @group_operators do
    raise ArgumentError,
          "expected #{inspect(operator)} to contain at least one filter, got: #{inspect(filters)}"
  end

  def from_filter(filter, {{arities, _names}, compiler}) do
    [name | arguments] = Tuple.to_list(filter)
    expected_arity = Map.fetch!(arities, name)

    if length(arguments) == expected_arity do
      apply(compiler, :to_expr, [name | arguments])
    else
      raise ArgumentError,
            "expected #{expected_arity} arguments for #{inspect(name)}, got: #{inspect(arguments)}"
    end
  end
end
