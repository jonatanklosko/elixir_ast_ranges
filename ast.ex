defmodule AST do
  @doc """
  Returns a list of all meaningful code ranges in the given code.

  The ranges are right-exclusive.
  """
  @spec ranges(String.t()) :: [{location, location}]
        when location: {line :: pos_integer(), column :: pos_integer()}
  def ranges(code) do
    {ast, comments} =
      Code.string_to_quoted_with_comments!(code,
        columns: true,
        token_metadata: true,
        unescape: false,
        literal_encoder: &{:ok, {:__block__, &2, [&1]}},
        emit_warnings: false
      )

    ctx = %{
      ranges: [],
      comment_range_after_line: %{},
      comment_range_before_line: %{}
    }

    ctx = comment_ranges(comments, nil, ctx)

    from_line =
      if comment = List.first(comments) do
        comment.line - comment.previous_eol_count
      end

    to_line =
      if comment = List.last(comments) do
        comment.line + comment.next_eol_count
      end

    {_range, ctx} = ast |> block_expressions() |> children_ranges(from_line, to_line, ctx)

    ctx.ranges
  end

  defp push_range(ctx, range) do
    update_in(ctx.ranges, &[range | &1])
  end

  defp peek_range(%{ranges: [range | _]}), do: range

  defp comment_ranges([comment | comments], group, ctx) do
    # Comment line
    from = {comment.line, comment.column}
    to = walk_content(from, comment.text, nil)
    ctx = push_range(ctx, {from, to})

    line_before = comment.line - comment.previous_eol_count
    line_after = comment.line + comment.next_eol_count

    # Group of adjacent comment lines
    {group, ctx} =
      case group do
        %{from: {_, column}, to: {line, _}}
        when comment.line == line + 1 and comment.column == column and
               comment.previous_eol_count == 1 ->
          group = %{group | to: to, line_after: line_after}
          {group, ctx}

        group ->
          ctx = finish_comment_group(group, ctx)
          group = %{from: from, to: to, line_after: line_after, line_before: line_before}
          {group, ctx}
      end

    comment_ranges(comments, group, ctx)
  end

  defp comment_ranges([], group, ctx), do: finish_comment_group(group, ctx)

  defp finish_comment_group(nil, ctx), do: ctx

  defp finish_comment_group(group, ctx) do
    # Only add a group range if there are multiple lines
    ctx =
      case {group.from, group.to} do
        {{line, _}, {line, _}} -> ctx
        {from, to} -> push_range(ctx, {from, to})
      end

    ctx = put_in(ctx.comment_range_after_line[group.line_before], {group.from, group.to})
    put_in(ctx.comment_range_before_line[group.line_after], {group.from, group.to})
  end

  # This is the entry point for recursive calls, because we need to
  # check each AST node for :parens, in case it is a block with single
  # expression. For stab operator, we handle :parens separately.
  defp child_ranges({target, meta, inner} = ast, ctx) when target != :-> do
    case keyword_pop_first(meta, :parens) do
      {nil, _meta} ->
        ranges(ast, ctx)

      {parens, meta} ->
        ast = {target, meta, inner}
        from = location(parens)
        to = parens[:closing] |> location() |> advance(1)
        {_range, ctx} = children_ranges([ast], line(from), line(to), ctx)
        push_range(ctx, {from, to})
    end
  end

  defp child_ranges(ast, ctx) do
    ranges(ast, ctx)
  end

  # Number
  def ranges({:__block__, meta, [number]}, ctx) when is_number(number) do
    from = location(meta)
    length = String.length(meta[:token])
    to = advance(from, length)
    push_range(ctx, {from, to})
  end

  # Atom
  def ranges({:__block__, meta, [atom]}, ctx) when is_atom(atom) do
    from = location(meta)
    content = Atom.to_string(atom)

    {pre_offset, post_offset} =
      cond do
        meta[:format] == :keyword -> {0, 1}
        atom in [nil, true, false] and meta[:format] != :atom -> {0, 0}
        true -> {1, 0}
      end

    if delimiter = meta[:delimiter] do
      # : and quotes
      content_from = advance(from, pre_offset + 1)
      content_to = walk_content(content_from, content, delimiter)
      to = advance(content_to, post_offset + 1)

      ctx
      |> push_range({content_from, content_to})
      |> push_range({from, to})
    else
      # :
      length = String.length(content)
      to = advance(from, pre_offset + length + post_offset)
      push_range(ctx, {from, to})
    end
  end

  # String
  def ranges({:__block__, meta, [string]}, ctx) when is_binary(string) do
    string_ranges(meta, [string], ctx)
  end

  def ranges({:__block__, meta, [list]}, ctx) when is_list(list) do
    if meta[:delimiter] do
      # Charlist
      string = List.to_string(list)
      string_ranges(meta, [string], ctx)
    else
      # List
      container_ranges(meta, list, 1, ctx)
    end
  end

  # 2-element tuple
  def ranges({:__block__, meta, [tuple]}, ctx) when is_tuple(tuple) do
    items = Tuple.to_list(tuple)
    container_ranges(meta, items, 1, ctx)
  end

  # n-element tuple
  def ranges({:{}, meta, items}, ctx) do
    container_ranges(meta, items, 1, ctx)
  end

  # Map
  def ranges({:%{}, meta, items}, ctx) do
    container_ranges(meta, items, 1, ctx)
  end

  # Struct
  def ranges({:%, meta, [left, {:%{}, map_meta, items}]}, ctx) do
    ctx = child_ranges(left, ctx)
    meta = Keyword.put(meta, :closing, map_meta[:closing])
    container_ranges(meta, items, 1, ctx)
  end

  # 2-element tuple, not literal-encoded (keyword list or map entry)
  def ranges({left, right}, ctx) do
    ctx =
      with {_ast, meta, _args} <- left,
           {:ok, assoc} <- Keyword.fetch(meta, :assoc) do
        # Assoc operator inside maps
        assoc_from = location(assoc)
        assoc_to = advance(assoc_from, 2)
        push_range(ctx, {assoc_from, assoc_to})
      else
        _ -> ctx
      end

    {_range, ctx} = children_ranges([left, right], nil, nil, ctx)
    ctx
  end

  # Keyword list in function call args, not literal-encoded
  def ranges(keyword, ctx) when is_list(keyword) do
    {_range, ctx} = children_ranges(keyword, nil, nil, ctx)
    ctx
  end

  # Interpolated atom
  def ranges({{:., _, [:erlang, :binary_to_atom]}, meta, [interpolation, :utf8]}, ctx) do
    # :
    {pre_offset, post_offset} =
      if meta[:format] == :keyword do
        {0, 1}
      else
        {1, 0}
      end

    {:<<>>, inner_meta, segments} = interpolation

    from = location(meta)
    delimiter_from = advance(from, pre_offset)
    delimiter = meta[:delimiter]
    indentation = inner_meta[:indentation]

    {delimiter_to, ctx} =
      string_content_ranges(delimiter_from, delimiter, indentation, segments, ctx)

    to = advance(delimiter_to, post_offset)
    push_range(ctx, {from, to})
  end

  # Interpolated charlists
  def ranges({{:., _, [List, :to_charlist]}, meta, [segments]}, ctx) do
    string_ranges(meta, segments, ctx)
  end

  def ranges({:<<>>, meta, args}, ctx) do
    if meta[:delimiter] do
      # Interpolated string
      string_ranges(meta, args, ctx)
    else
      # Bitstring
      container_ranges(meta, args, 2, ctx)
    end
  end

  # Sigil
  def ranges({sigil, meta, [{:<<>>, inner_meta, segments}, modifiers]}, ctx)
      when is_atom(sigil) and is_list(modifiers) do
    # We know it's a sigil, because modifiers arg is a plain list,
    # not wrapped by literal encoder
    "sigil_" <> name = Atom.to_string(sigil)

    # ~ and sigil name
    pre_offset = 1 + String.length(name)
    post_offset = length(modifiers)

    from = location(meta)
    delimiter_from = advance(from, pre_offset)
    delimiter = meta[:delimiter]
    indentation = inner_meta[:indentation]

    {delimiter_to, ctx} =
      string_content_ranges(delimiter_from, delimiter, indentation, segments, ctx)

    to = advance(delimiter_to, post_offset)
    push_range(ctx, {from, to})
  end

  # Alias
  def ranges({:__aliases__, meta, segments}, ctx) do
    {from, ctx} =
      case segments do
        # The first segment may be a AST node, such as __MODULE__
        [{_, _, _} = left | _] ->
          ctx = child_ranges(left, ctx)
          {from, _} = peek_range(ctx)
          {from, ctx}

        _other ->
          {location(meta), ctx}
      end

    last_segment_length = segments |> List.last() |> Atom.to_string() |> String.length()
    to = meta[:last] |> location() |> advance(last_segment_length)
    push_range(ctx, {from, to})
  end

  # Variable
  def ranges({name, meta, nil}, ctx) when is_atom(name) do
    from = location(meta)
    length = name |> Atom.to_string() |> String.length()
    to = advance(from, length)
    push_range(ctx, {from, to})
  end

  # Block
  def ranges({:__block__, meta, nodes}, ctx) do
    if closing = meta[:closing] do
      from = location(meta)
      to = closing |> location() |> advance(1)
      {_range, ctx} = children_ranges(nodes, line(from), line(to), ctx)
      push_range(ctx, {from, to})
    else
      {_range, ctx} = children_ranges(nodes, nil, nil, ctx)
      ctx
    end
  end

  # Anonymous function
  def ranges({:fn, meta, clauses}, ctx) do
    fn_from = location(meta)
    fn_to = advance(fn_from, 2)
    ctx = push_range(ctx, {fn_from, fn_to})

    end_from = location(meta[:closing])
    end_to = advance(end_from, 3)

    {_range, ctx} = children_ranges(clauses, line(fn_from), line(end_from), ctx)

    ctx |> push_range({end_from, end_to}) |> push_range({fn_from, end_to})
  end

  # Stab clause
  def ranges({:->, meta, [left, right]}, ctx) do
    stab_from = location(meta)
    stab_to = advance(stab_from, 2)
    stab_range = {stab_from, stab_to}
    ctx = push_range(ctx, stab_range)

    {children_range, ctx} = children_ranges(left, nil, nil, ctx)

    {clause_from, ctx} =
      if parens = meta[:parens] do
        from = location(parens)
        to = parens[:closing] |> location() |> advance(1)
        {from, push_range(ctx, {from, to})}
      else
        case children_range do
          {from, _} -> {from, ctx}
          nil -> {stab_from, ctx}
        end
      end

    {clause_to, ctx} =
      with {:__block__, right_meta, [nil]} <- right,
           true <- meta[:column] == right_meta[:column] do
        {stab_to, ctx}
      else
        _ ->
          {{_, block_to}, ctx} =
            right |> block_expressions() |> children_ranges(line(stab_from), nil, ctx)

          {block_to, ctx}
      end

    clause_range = {clause_from, clause_to}

    if clause_range == stab_range do
      ctx
    else
      push_range(ctx, clause_range)
    end
  end

  # Capture argument operand
  def ranges({:&, meta, [number]}, ctx) when is_integer(number) do
    from = location(meta)
    length = number |> Integer.to_string() |> String.length()
    to = advance(from, 1 + length)
    push_range(ctx, {from, to})
  end

  # Access call
  def ranges({{:., _, [Access, :get]}, meta, [left, right]}, ctx) do
    ctx = child_ranges(left, ctx)
    {from, _} = peek_range(ctx)
    ctx = child_ranges(right, ctx)
    to = meta[:closing] |> location() |> advance(1)
    push_range(ctx, {from, to})
  end

  # Qualified tuple
  def ranges({{:., dot_meta, [left, :{}]}, meta, args}, ctx) do
    dot_from = location(dot_meta)
    dot_to = advance(dot_from, 1)
    ctx = push_range(ctx, {dot_from, dot_to})

    to = meta[:closing] |> location() |> advance(1)

    ctx = child_ranges(left, ctx)
    {from, _} = peek_range(ctx)

    {_args_range, ctx} = children_ranges(args, line(dot_from), line(to), ctx)

    push_range(ctx, {from, to})
  end

  # Dot call
  def ranges({{:., dot_meta, [left | maybe_right]}, meta, args}, ctx) do
    dot_from = location(dot_meta)
    dot_to = advance(dot_from, 1)
    ctx = push_range(ctx, {dot_from, dot_to})

    # Left
    ctx = child_ranges(left, ctx)
    {target_from, _} = peek_range(ctx)

    # Right
    {target_to, ctx} =
      case maybe_right do
        # Anonymous function
        [] ->
          {dot_to, ctx}

        # Qualified call
        [right] when is_atom(right) ->
          from = location(meta)
          content = Atom.to_string(right)

          if delimiter = meta[:delimiter] do
            content_from = advance(from, 1)
            content_to = walk_content(content_from, content, delimiter)
            to = advance(content_to, 1)
            ctx = push_range(ctx, {content_from, content_to})
            ctx = push_range(ctx, {from, to})
            {to, ctx}
          else
            to = advance(from, String.length(content))
            ctx = push_range(ctx, {from, to})
            {to, ctx}
          end
      end

    ctx = push_range(ctx, {target_from, target_to})

    {args, ctx} = do_end_ranges(meta, args, ctx)
    args_to_line = meta[:closing][:line] || meta[:do][:line]
    {args_range, ctx} = children_ranges(args, line(dot_from), args_to_line, ctx)

    if call_to = call_to(meta, args_range) do
      push_range(ctx, {target_from, call_to})
    else
      ctx
    end
  end

  # Unqualified call or operator
  def ranges({name, meta, args}, ctx) when is_atom(name) do
    from = location(meta)
    length = name |> Atom.to_string() |> String.length()
    name_to = advance(from, length)

    ctx = push_range(ctx, {from, name_to})

    {args, ctx} = do_end_ranges(meta, args, ctx)
    args_to_line = meta[:closing][:line] || meta[:do][:line]
    {args_range, ctx} = children_ranges(args, line(from), args_to_line, ctx)

    case args_range do
      {args_from, _} when args_from < from ->
        # It's an operator and left-to-right operand range already
        # covers the whole call
        ctx

      _ ->
        if call_to = call_to(meta, args_range) do
          push_range(ctx, {from, call_to})
        else
          ctx
        end
    end
  end

  # Double call, such as unquote(foo)()
  def ranges({target, meta, args}, ctx) do
    ctx = child_ranges(target, ctx)
    {target_from, _} = peek_range(ctx)

    {args, ctx} = do_end_ranges(meta, args, ctx)
    args_to_line = meta[:closing][:line] || meta[:do][:line]
    {args_range, ctx} = children_ranges(args, line(target_from), args_to_line, ctx)

    call_to = call_to(meta, args_range)
    push_range(ctx, {target_from, call_to})
  end

  # Handles a group of sibling expressions, adding leading/trailing
  # comments to the full range if any
  defp children_ranges(children, from_line, to_line, ctx) do
    {ranges, ctx} =
      Enum.map_reduce(children, ctx, fn arg, ctx ->
        ctx = child_ranges(arg, ctx)
        range = peek_range(ctx)
        {range, ctx}
      end)

    leading_comment = from_line && ctx.comment_range_after_line[from_line]
    trailing_comment = to_line && ctx.comment_range_before_line[to_line]

    leading_comment_from = leading_comment && elem(leading_comment, 0)
    trailing_comment_to = trailing_comment && elem(trailing_comment, 1)

    case ranges do
      [{from, _}, _ | _] ->
        {_, to} = List.last(ranges)
        range = {maybe_min(leading_comment_from, from), maybe_max(trailing_comment_to, to)}
        {range, push_range(ctx, range)}

      [{from, to}] ->
        if (leading_comment != nil and leading_comment_from < from) or
             (trailing_comment != nil and trailing_comment_to > to) do
          range = {maybe_min(leading_comment_from, from), maybe_max(trailing_comment_to, to)}
          {range, push_range(ctx, range)}
        else
          {{from, to}, ctx}
        end

      [] ->
        if leading_comment != nil and trailing_comment != nil and
             leading_comment != trailing_comment do
          range = {leading_comment_from, trailing_comment_to}
          {range, push_range(ctx, range)}
        else
          {nil, ctx}
        end
    end
  end

  defp block_expressions({:__block__, _meta, [_]} = node) do
    # Wrapped literal
    [node]
  end

  defp block_expressions({:__block__, meta, nodes} = node) do
    if meta[:parens] || meta[:closing] do
      # Treat blocks with parens as a single expression
      [node]
    else
      nodes
    end
  end

  defp block_expressions(node), do: [node]

  defp container_ranges(meta, items, closing_length, ctx) do
    from = location(meta)
    to = meta[:closing] |> location() |> advance(closing_length)
    {_range, ctx} = children_ranges(items, line(from), line(to), ctx)
    push_range(ctx, {from, to})
  end

  defp string_ranges(meta, entries, ctx) do
    delimiter_from = location(meta)
    delimiter = meta[:delimiter]
    indentation = meta[:indentation]

    {delimiter_to, ctx} =
      string_content_ranges(delimiter_from, delimiter, indentation, entries, ctx)

    push_range(ctx, {delimiter_from, delimiter_to})
  end

  defp string_content_ranges(delimiter_from, delimiter, indentation, entries, ctx) do
    delimiter_length = String.length(delimiter)
    indentation = indentation || 0

    content_from = advance(delimiter_from, delimiter_length)

    entries_from =
      if delimiter_length == 3 do
        # Heredoc
        content_from |> advance_line(1) |> advance(indentation)
      else
        content_from
      end

    {ctx, suffix_from, suffix} =
      Enum.reduce(entries, {ctx, entries_from, ""}, fn
        entry, {ctx, content_from, _suffix} when is_binary(entry) ->
          {ctx, content_from, entry}

        entry, {ctx, _content_from, _suffix} ->
          entry =
            case entry do
              # String interpolation entry
              {:"::", _, [entry, {:binary, _, _}]} -> entry
              # Charlist interpolation entry
              entry -> entry
            end

          {{:., _, [Kernel, :to_string]}, meta, [inner]} = entry

          from = location(meta)
          to = meta[:closing] |> location() |> advance(1)

          {_range, ctx} =
            inner |> block_expressions() |> children_ranges(line(from), line(to), ctx)

          ctx = push_range(ctx, {from, to})
          {ctx, to, ""}
      end)

    content_to =
      suffix_from
      |> walk_content(suffix, delimiter)
      |> advance(indentation)

    delimiter_to = advance(content_to, delimiter_length)

    ctx = push_range(ctx, {content_from, content_to})
    {delimiter_to, ctx}
  end

  defp do_end_ranges(meta, args, ctx) do
    if meta[:do] do
      {args, [[do_block | blocks]]} = Enum.split(args, -1)

      {{:__block__, _, [:do]}, ast} = do_block

      do_from = location(meta[:do])
      end_from = location(meta[:end])
      do_to = advance(do_from, 2)
      end_to = advance(end_from, 3)

      ctx = push_range(ctx, {do_from, do_to})

      block_lines = Enum.map(blocks, fn {{:__block__, meta, _}, _} -> meta[:line] end)
      [do_block_end_line | block_end_lines] = block_lines ++ [line(end_from)]

      {_range, ctx} =
        ast |> block_expressions() |> children_ranges(line(do_from), do_block_end_line, ctx)

      ctx =
        blocks
        |> Enum.zip(block_end_lines)
        |> Enum.reduce(ctx, fn {block, block_end_line}, ctx ->
          {{:__block__, meta, [name]}, ast} = block
          name_from = location(meta)
          name_length = name |> Atom.to_string() |> String.length()
          name_to = advance(name_from, name_length)
          ctx = push_range(ctx, {name_from, name_to})

          {children_range, ctx} =
            ast |> block_expressions() |> children_ranges(line(name_from), block_end_line, ctx)

          case children_range do
            {_, block_to} -> push_range(ctx, {name_from, block_to})
            nil -> ctx
          end
        end)

      ctx = ctx |> push_range({end_from, end_to}) |> push_range({do_from, end_to})

      {args, ctx}
    else
      {args, ctx}
    end
  end

  defp call_to(meta, args_range) do
    cond do
      end_closing = meta[:end] ->
        end_closing |> location() |> advance(3)

      closing = meta[:closing] ->
        closing |> location() |> advance(1)

      args_range ->
        elem(args_range, 1)

      true ->
        nil
    end
  end

  defp location(meta) do
    {meta[:line], meta[:column]}
  end

  defp advance({line, column}, n) do
    {line, column + n}
  end

  defp advance_line({line, _column}, n) do
    {line + n, 1}
  end

  defp line({line, _column}), do: line

  defp walk_content({line, column}, "", _delimiter), do: {line, column}

  defp walk_content({line, column}, string, delimiter) do
    case string do
      <<^delimiter::binary, string::binary>> ->
        # Delimiters are always unescaped, so if we run into one, it
        # means the source code has an additional backslash
        walk_content({line, column + 1 + String.length(delimiter)}, string, delimiter)

      string ->
        {grapheme, string} = String.next_grapheme(string)

        if grapheme =~ "\n" do
          walk_content({line + 1, 1}, string, delimiter)
        else
          walk_content({line, column + 1}, string, delimiter)
        end
    end
  end

  defp keyword_pop_first([], _key), do: {nil, []}

  defp keyword_pop_first([{key, value} | list], key), do: {value, list}

  defp keyword_pop_first([kw | list], key) do
    {value, list} = keyword_pop_first(list, key)
    {value, [kw | list]}
  end

  defp maybe_min(nil, right), do: right
  defp maybe_min(left, nil), do: left
  defp maybe_min(left, right), do: min(left, right)

  defp maybe_max(nil, right), do: right
  defp maybe_max(left, nil), do: left
  defp maybe_max(left, right), do: max(left, right)
end
