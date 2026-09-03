defmodule Fltr.Filter do
  @moduledoc """
  Types and parsing implementation for filter expressions.

  Most users should define a filter module with `use Fltr` and call the generated
  `parse/1` and `to_expr/1` functions.
  """

  @group_operators [:any, :all]

  @type group_operator :: :any | :all

  @type parse_error ::
          {:invalid_filter, term()}
          | {:unknown_filter, String.t() | atom()}
          | {:invalid_arguments, atom(), term()}

  @type config :: Fltr.Config.t()

  @type parser :: (atom(), term() -> {:ok, term()} | :error)

  @typedoc "A validated tuple for one declared filter."
  @type filter :: tuple()

  @typedoc "A filter or an `any`/`all` group containing at least one expression."
  @type t :: filter() | {group_operator(), [t(), ...]}

  @doc false
  @spec parse(term(), config(), parser()) ::
          {:ok, t()} | {:error, parse_error()}
  def parse([operator | args], config, parser)
      when operator in ["any", "all"] and is_list(args) do
    parse([String.to_existing_atom(operator) | args], config, parser)
  end

  def parse([operator, filters], config, parser)
      when operator in @group_operators and is_list(filters) and
             filters != [] do
    with {:ok, parsed_filters} <- parse_filters(filters, config, parser) do
      {:ok, {operator, parsed_filters}}
    end
  end

  def parse([operator, []], _config, _parser)
      when operator in @group_operators do
    {:error, {:invalid_arguments, operator, []}}
  end

  def parse([operator | args], _config, _parser)
      when operator in @group_operators and is_list(args) do
    {:error, {:invalid_arguments, operator, args}}
  end

  def parse([name | args], {arities, _external_names}, parser)
      when is_atom(name) and is_list(args) do
    case Map.fetch(arities, name) do
      {:ok, arity} -> parse_arguments(name, args, arity, parser)
      :error -> {:error, {:unknown_filter, name}}
    end
  end

  def parse([name | args], {arities, external_names}, parser)
      when is_binary(name) and is_list(args) do
    case Map.fetch(external_names, name) do
      {:ok, parsed_name} ->
        arity = Map.fetch!(arities, parsed_name)
        parse_arguments(parsed_name, args, arity, parser)

      :error ->
        {:error, {:unknown_filter, name}}
    end
  end

  def parse([_name | args] = filter, _config, _parser)
      when is_list(args) do
    {:error, {:invalid_filter, filter}}
  end

  def parse(filter, {arities, _names} = config, parser)
      when is_tuple(filter) and tuple_size(filter) > 0 and
             (is_atom(elem(filter, 0)) or is_binary(elem(filter, 0))) do
    [name | args] = Tuple.to_list(filter)

    if is_atom(name) and Map.has_key?(arities, name) do
      if length(args) == Map.fetch!(arities, name) do
        {:ok, filter}
      else
        {:error, {:invalid_arguments, name, args}}
      end
    else
      parse(Tuple.to_list(filter), config, parser)
    end
  end

  def parse(filter, _config, _parser), do: {:error, {:invalid_filter, filter}}

  # private

  defp parse_arguments(name, [], 0, _parser), do: {:ok, {name}}

  defp parse_arguments(name, args, arity, parser)
       when length(args) == arity do
    input =
      case args do
        [argument] -> argument
        arguments -> List.to_tuple(arguments)
      end

    case parser.(name, input) do
      {:ok, value} when arity == 1 ->
        {:ok, {name, value}}

      {:ok, values} when is_tuple(values) and tuple_size(values) == arity ->
        {:ok, Tuple.insert_at(values, 0, name)}

      {:ok, _value} ->
        {:error, {:invalid_arguments, name, args}}

      :error ->
        {:error, {:invalid_arguments, name, args}}
    end
  end

  defp parse_arguments(name, args, _arity, _parser) do
    {:error, {:invalid_arguments, name, args}}
  end

  defp parse_filters([], _config, _parser), do: {:ok, []}

  defp parse_filters([filter | filters], config, parser) do
    with {:ok, parsed_filter} <- parse(filter, config, parser),
         {:ok, parsed_filters} <- parse_filters(filters, config, parser) do
      {:ok, [parsed_filter | parsed_filters]}
    end
  end
end
