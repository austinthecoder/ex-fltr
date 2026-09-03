# Fltr

Fltr defines small filter modules that parse external input into a canonical
filter expression and compile that expression into an
`Ecto.Query.dynamic/2` value.

## Installation

Add `fltr` to the dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:fltr, "~> 0.1.0"}
  ]
end
```

Fltr supports Elixir 1.14 or later and Ecto versions from 3.10 up to, but not
including, 4.0.

## Usage

Define the supported filters and implement one `to_expr` clause for each filter:

```elixir
defmodule TeamFilter do
  use Fltr, filters: [active: 0, id: 1, name: 1]

  def parse(:id, id) when is_binary(id) do
    case Integer.parse(id) do
      {id, ""} -> {:ok, id}
      _other -> :error
    end
  end

  def parse(:id, _id), do: :error

  def to_expr(:active), do: dynamic([team], team.active)
  def to_expr(:id, id), do: dynamic([team], team.id == ^id)
  def to_expr(:name, name), do: dynamic([team], team.name == ^name)
end
```

Parse external input before compiling it:

```elixir
{:ok, filter} =
  TeamFilter.parse([
    "all",
    [
      ["id", "7"],
      ["active"]
    ]
  ])

dynamic = TeamFilter.to_expr(filter)
```

The canonical expression produced above is:

```elixir
{:all, [{:id, 7}, {:active}]}
```

Lists and string-named tuples are treated as external input and pass through the
configured parser. Atom-named tuples are trusted canonical expressions: Fltr
checks their argument count but does not parse their values again.
