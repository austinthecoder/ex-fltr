defmodule Fltr.Config do
  @moduledoc false

  @reserved_names [:any, :all]

  @type t :: {
          %{optional(atom()) => non_neg_integer()},
          %{optional(String.t()) => atom()}
        }

  @spec build(term()) :: t()
  def build(opts) do
    unless Keyword.keyword?(opts) do
      raise ArgumentError,
            "expected options passed to use Fltr to be a keyword list"
    end

    unknown_options = Keyword.keys(opts) -- [:filters]

    if unknown_options != [] do
      raise ArgumentError,
            "unknown Fltr options: #{inspect(unknown_options)}"
    end

    filters = Keyword.get(opts, :filters)

    unless Keyword.keyword?(filters) and filters != [] do
      raise ArgumentError,
            "expected :filters to be a non-empty keyword list of names and argument counts"
    end

    names = Keyword.keys(filters)

    if names != Enum.uniq(names) do
      raise ArgumentError, "filter names must be unique"
    end

    Enum.each(filters, fn
      {name, _arity} when name in @reserved_names ->
        raise ArgumentError, "#{inspect(name)} is reserved by Fltr"

      {_name, arity} when is_integer(arity) and arity >= 0 ->
        :ok

      {name, _arity} ->
        raise ArgumentError,
              "expected the argument count for #{inspect(name)} to be a non-negative integer"
    end)

    arities = Map.new(filters)
    external_names = Map.new(names, &{Atom.to_string(&1), &1})

    {arities, external_names}
  end
end
