Code.require_file("ast.ex", __DIR__)

ExUnit.start()

defmodule ASTTest do
  use ExUnit.Case, async: true

  test "number" do
    assert ~S"""
           1
           """
           |> mark_ranges() == ~S"""
           «1»
           """

    assert ~S"""
           1_000
           """
           |> mark_ranges() == ~S"""
           «1_000»
           """

    assert ~S"""
           1.1
           """
           |> mark_ranges() == ~S"""
           «1.1»
           """

    assert ~S"""
           1.1e10
           """
           |> mark_ranges() == ~S"""
           «1.1e10»
           """
  end

  test "atom" do
    assert ~S"""
           :hello
           """
           |> mark_ranges() ==
             ~S"""
             «:hello»
             """

    assert ~S"""
           :"hello 🐈"
           """
           |> mark_ranges() ==
             ~S"""
             «:"«hello 🐈»"»
             """

    assert ~S"""
           :"hello \" \t"
           """
           |> mark_ranges() ==
             ~S"""
             «:"«hello \" \t»"»
             """

    assert ~S"""
           :"hello
             welcome"
           """
           |> mark_ranges() ==
             ~S"""
             «:"«hello
               welcome»"»
             """

    assert ~S"""
           :"hello #{1} welcome"
           """
           |> mark_ranges() ==
             ~S"""
             «:"«hello «#{«1»}» welcome»"»
             """

    assert ~S"""
           :true
           """
           |> mark_ranges() ==
             ~S"""
             «:true»
             """
  end

  test "strings" do
    assert ~S"""
           "hello welcome"
           """
           |> mark_ranges() ==
             ~S"""
             «"«hello welcome»"»
             """

    assert ~S"""
           "hello #{ 1 + 1 } welcome"
           """
           |> mark_ranges() ==
             ~S"""
             «"«hello «#{ ««1» «+» «1»» }» welcome»"»
             """

    assert ~S'''
               """
             hello
             welcome
             """
           '''
           |> mark_ranges() ==
             ~S'''
                 «"""«
               hello
               welcome
               »"""»
             '''

    assert ~S'''
               """
             hello
             #{ 1 + 1 }
             welcome
             """
           '''
           |> mark_ranges() ==
             ~S'''
                 «"""«
               hello
               «#{ ««1» «+» «1»» }»
               welcome
               »"""»
             '''

    assert ~S"""
           "hello \" welcome"
           """
           |> mark_ranges() ==
             ~S"""
             «"«hello \" welcome»"»
             """

    assert ~S'''
           """
           hello \""" \n welcome
           """
           '''
           |> mark_ranges() ==
             ~S'''
             «"""«
             hello \""" \n welcome
             »"""»
             '''
  end

  test "charlist" do
    assert ~S"""
           'hello welcome'
           """
           |> mark_ranges() ==
             ~S"""
             «'«hello welcome»'»
             """

    assert ~S"""
           'hello #{ 1 + 1 } welcome'
           """
           |> mark_ranges() ==
             ~S"""
             «'«hello «#{ ««1» «+» «1»» }» welcome»'»
             """

    assert ~S"""
               '''
             hello
             welcome
             '''
           """
           |> mark_ranges() ==
             ~S"""
                 «'''«
               hello
               welcome
               »'''»
             """

    assert ~S"""
               '''
             hello
             #{ 1 + 1 }
             welcome
             '''
           """
           |> mark_ranges() ==
             ~S"""
                 «'''«
               hello
               «#{ ««1» «+» «1»» }»
               welcome
               »'''»
             """

    assert ~S"""
           'hello \' welcome'
           """
           |> mark_ranges() ==
             ~S"""
             «'«hello \' welcome»'»
             """

    assert ~S"""
           '''
           hello \''' \n welcome
           '''
           """
           |> mark_ranges() ==
             ~S"""
             «'''«
             hello \''' \n welcome
             »'''»
             """
  end

  test "sigils" do
    assert ~S"""
           ~NAME"hello welcome"g
           """
           |> mark_ranges() ==
             ~S"""
             «~NAME"«hello welcome»"g»
             """

    assert ~S"""
           ~s"hello #{ 1 + 1 } welcome"
           """
           |> mark_ranges() ==
             ~S"""
             «~s"«hello «#{ ««1» «+» «1»» }» welcome»"»
             """

    assert ~S'''
               ~s"""
             hello
             #{ 1 + 1 }
             welcome
             """
           '''
           |> mark_ranges() ==
             ~S'''
                 «~s"""«
               hello
               «#{ ««1» «+» «1»» }»
               welcome
               »"""»
             '''

    assert ~S'''
               ~S"""
             hello
             #{1 + 1}
             welcome
             """
           '''
           |> mark_ranges() ==
             ~S'''
                 «~S"""«
               hello
               #{1 + 1}
               welcome
               »"""»
             '''

    # Local call, not a sigil
    assert ~S'''
           sigil_S(<<>>, [])
           '''
           |> mark_ranges() ==
             ~S'''
             ««sigil_S»(««<<>>», «[]»»)»
             '''
  end

  test "bitstring" do
    assert ~S"""
           << 1::64-integer-unsigned, data::binary >>
           """
           |> mark_ranges() ==
             ~S"""
             «<< «««1»«::»«««64»«-»«integer»»«-»«unsigned»»», ««data»«::»«binary»»» >>»
             """
  end

  test "list" do
    assert ~S"""
           [ ]
           """
           |> mark_ranges() ==
             ~S"""
             «[ ]»
             """

    assert ~S"""
           [ 1 ]
           """
           |> mark_ranges() ==
             ~S"""
             «[ «1» ]»
             """

    assert ~S"""
           [ 1, 2 ]
           """
           |> mark_ranges() ==
             ~S"""
             «[ ««1», «2»» ]»
             """
  end

  test "tuple" do
    assert ~S"""
           { }
           """
           |> mark_ranges() ==
             ~S"""
             «{ }»
             """

    assert ~S"""
           { 1 }
           """
           |> mark_ranges() ==
             ~S"""
             «{ «1» }»
             """

    assert ~S"""
           { 1, 2 }
           """
           |> mark_ranges() ==
             ~S"""
             «{ ««1», «2»» }»
             """

    assert ~S"""
           { 1, 2, 3 }
           """
           |> mark_ranges() ==
             ~S"""
             «{ ««1», «2», «3»» }»
             """
  end

  test "map" do
    assert ~S"""
           %{ key1: 1, key2: 2 }
           """
           |> mark_ranges() ==
             ~S"""
             «%{ «««key1:» «1»», ««key2:» «2»»» }»
             """

    assert ~S"""
           %{ :key1 => 1, :key2 => 2 }
           """
           |> mark_ranges() ==
             ~S"""
             «%{ «««:key1» «=>» «1»», ««:key2» «=>» «2»»» }»
             """
  end

  test "struct" do
    assert ~S"""
           %My.Struct{
             foo: 1,
             bar: 2
           }
           """
           |> mark_ranges() ==
             ~S"""
             «%«My.Struct»{
               «««foo:» «1»»,
               ««bar:» «2»»»
             }»
             """
  end

  test "keyword list" do
    assert ~S"""
           [ hello: 1, welcome: 2 ]
           """
           |> mark_ranges() ==
             ~S"""
             «[ «««hello:» «1»», ««welcome:» «2»»» ]»
             """

    assert ~S"""
           ["hello 🐈": 1]
           """
           |> mark_ranges() ==
             ~S"""
             «[««"«hello 🐈»":» «1»»]»
             """

    assert ~S"""
           ["hello
           🐈": 1]
           """
           |> mark_ranges() ==
             ~S"""
             «[««"«hello
             🐈»":» «1»»]»
             """

    assert ~S"""
           ["hello #{1} welcome": 1]
           """
           |> mark_ranges() ==
             ~S"""
             «[««"«hello «#{«1»}» welcome»":» «1»»]»
             """
  end

  test "keyword in function call" do
    assert ~S"""
           foo(hello: 1, welcome: 2)
           """
           |> mark_ranges() ==
             ~S"""
             ««foo»(«««hello:» «1»», ««welcome:» «2»»»)»
             """
  end

  test "alias" do
    assert ~S"""
           Foo.Bar
           """
           |> mark_ranges() ==
             ~S"""
             «Foo.Bar»
             """

    assert ~S"""
           __MODULE__.Bar
           """
           |> mark_ranges() ==
             ~S"""
             ««__MODULE__».Bar»
             """

    assert ~S"""
           foo.bar.().Baz
           """
           |> mark_ranges() ==
             ~S"""
             «««««foo»«.»«bar»»«.»»()».Baz»
             """

    assert ~S"""
           Foo.{Bar, Baz}
           """
           |> mark_ranges() ==
             ~S"""
             ««Foo»«.»{««Bar», «Baz»»}»
             """
  end

  test "variable" do
    assert ~S"""
           foo
           """
           |> mark_ranges() ==
             ~S"""
             «foo»
             """

    assert ~S"""
           foo?
           """
           |> mark_ranges() ==
             ~S"""
             «foo?»
             """
  end

  test "block" do
    assert ~S"""
           ( 1 )
           """
           |> mark_ranges() ==
             ~S"""
             «( «1» )»
             """

    assert ~S"""
           (( 1 ))
           """
           |> mark_ranges() ==
             ~S"""
             «(«( «1» )»)»
             """

    assert ~S"""
           ( 1 ; 1 )
           """
           |> mark_ranges() ==
             ~S"""
             «( ««1» ; «1»» )»
             """

    assert ~S"""
           (
             1
             1
           )
           """
           |> mark_ranges() ==
             ~S"""
             «(
               ««1»
               «1»»
             )»
             """
  end

  test "outermost block" do
    assert ~S"""
           1 ; 1
           """
           |> mark_ranges() ==
             ~S"""
             ««1» ; «1»»
             """

    assert ~S"""
           1
           1
           """
           |> mark_ranges() ==
             ~S"""
             ««1»
             «1»»
             """
  end

  test "anonymous function" do
    assert ~S"""
           fn -> end
           """
           |> mark_ranges() ==
             ~S"""
             ««fn» «->» «end»»
             """

    assert ~S"""
           fn -> 1 end
           """
           |> mark_ranges() ==
             ~S"""
             ««fn» ««->» «1»» «end»»
             """

    assert ~S"""
           fn -> nil end
           """
           |> mark_ranges() ==
             ~S"""
             ««fn» ««->» «nil»» «end»»
             """

    assert ~S"""
           fn x -> end
           """
           |> mark_ranges() ==
             ~S"""
             ««fn» ««x» «->»» «end»»
             """

    assert ~S"""
           fn x -> :ok end
           """
           |> mark_ranges() ==
             ~S"""
             ««fn» ««x» «->» «:ok»» «end»»
             """

    assert ~S"""
           fn x, y -> end
           """
           |> mark_ranges() ==
             ~S"""
             ««fn» «««x», «y»» «->»» «end»»
             """

    assert ~S"""
           fn (x, y) -> :ok end
           """
           |> mark_ranges() ==
             ~S"""
             ««fn» ««(««x», «y»»)» «->» «:ok»» «end»»
             """

    assert ~S"""
           fn
             x, y ->
              :foo
              :bar

             x, y ->
              :foo
              :bar
           end
           """
           |> mark_ranges() ==
             ~S"""
             ««fn»
               ««««x», «y»» «->»
                ««:foo»
                «:bar»»»

               «««x», «y»» «->»
                ««:foo»
                «:bar»»»»
             «end»»
             """

    assert ~S"""
           fn x when x == 1 -> :ok end
           """
           |> mark_ranges() ==
             ~S"""
             ««fn» «««x» «when» ««x» «==» «1»»» «->» «:ok»» «end»»
             """
  end

  test "function capture" do
    assert ~S"""
           &foo(&1, 1)
           """
           |> mark_ranges() ==
             ~S"""
             ««&»««foo»(««&1», «1»»)»»
             """
  end

  test "access call" do
    assert ~S"""
           foo[bar]
           """
           |> mark_ranges() ==
             ~S"""
             ««foo»[«bar»]»
             """
  end

  test "qualified call" do
    assert ~S"""
           Foo.bar
           """
           |> mark_ranges() ==
             ~S"""
             ««Foo»«.»«bar»»
             """

    assert ~S"""
           Foo.bar()
           """
           |> mark_ranges() ==
             ~S"""
             «««Foo»«.»«bar»»()»
             """

    assert ~S"""
           Foo.bar(1, 2)
           """
           |> mark_ranges() ==
             ~S"""
             «««Foo»«.»«bar»»(««1», «2»»)»
             """

    assert ~S"""
           Foo."bar 🐈"
           """
           |> mark_ranges() ==
             ~S"""
             ««Foo»«.»«"«bar 🐈»"»»
             """

    assert ~S"""
           foo.bar
           """
           |> mark_ranges() ==
             ~S"""
             ««foo»«.»«bar»»
             """

    assert ~S"""
           @foo.bar
           """
           |> mark_ranges() ==
             ~S"""
             «««@»«foo»»«.»«bar»»
             """
  end

  test "anonymous function call" do
    assert ~S"""
           foo.()
           """
           |> mark_ranges() ==
             ~S"""
             «««foo»«.»»()»
             """

    assert ~S"""
           foo.(1, 2)
           """
           |> mark_ranges() ==
             ~S"""
             «««foo»«.»»(««1», «2»»)»
             """
  end

  test "unqualified call" do
    assert ~S"""
           foo()
           """
           |> mark_ranges() ==
             ~S"""
             ««foo»()»
             """

    assert ~S"""
           foo 1, 2
           """
           |> mark_ranges() ==
             ~S"""
             ««foo» ««1», «2»»»
             """

    assert ~S"""
           foo(1, 2)
           """
           |> mark_ranges() ==
             ~S"""
             ««foo»(««1», «2»»)»
             """
  end

  test "operator" do
    assert ~S"""
           -1
           """
           |> mark_ranges() ==
             ~S"""
             ««-»«1»»
             """

    assert ~S"""
           1 + 2
           """
           |> mark_ranges() ==
             ~S"""
             ««1» «+» «2»»
             """

    assert ~S"""
           ...
           """
           |> mark_ranges() ==
             ~S"""
             «...»
             """
  end

  test "double call" do
    assert ~S"""
           unquote(foo)(bar, baz)
           """
           |> mark_ranges() ==
             ~S"""
             «««unquote»(«foo»)»(««bar», «baz»»)»
             """

    assert ~S"""
           Kernel.unquote(foo)(bar, baz)
           """
           |> mark_ranges() ==
             ~S"""
             ««««Kernel»«.»«unquote»»(«foo»)»(««bar», «baz»»)»
             """
  end

  test "do-end block" do
    assert ~S"""
           foo x do end
           """
           |> mark_ranges() ==
             ~S"""
             ««foo» «x» ««do» «end»»»
             """

    assert ~S"""
           foo x do else end
           """
           |> mark_ranges() ==
             ~S"""
             ««foo» «x» ««do» «else» «end»»»
             """

    assert ~S"""
           foo x do
             1
             2
           else
             1
             2
           end
           """
           |> mark_ranges() ==
             ~S"""
             ««foo» «x» ««do»
               ««1»
               «2»»
             ««else»
               ««1»
               «2»»»
             «end»»»
             """

    assert ~S"""
           Foo.bar(x) do
             1
           end
           """
           |> mark_ranges() ==
             ~S"""
             «««Foo»«.»«bar»»(«x») ««do»
               «1»
             «end»»»
             """

    assert ~S"""
           foo x do
             1
           else
             x -> x
           end
           """
           |> mark_ranges() ==
             ~S"""
             ««foo» «x» ««do»
               «1»
             ««else»
               ««x» «->» «x»»»
             «end»»»
             """

    assert ~S"""
           unquote(foo)(bar, baz) do
             bar
           end
           """
           |> mark_ranges() ==
             ~S"""
             «««unquote»(«foo»)»(««bar», «baz»») ««do»
               «bar»
             «end»»»
             """
  end

  test "integration" do
    assert ~S"""
           [{1, %{2 => 2}}, 3]
           """
           |> mark_ranges() ==
             ~S"""
             «[««{««1», «%{««2» «=>» «2»»}»»}», «3»»]»
             """

    assert ~S"""
           foo(bar, baz) + 1
           """
           |> mark_ranges() ==
             ~S"""
             «««foo»(««bar», «baz»»)» «+» «1»»
             """

    assert ~S"""
           foo(x, key1: 1, key2: 2)
           """
           |> mark_ranges() ==
             ~S"""
             ««foo»(««x», «««key1:» «1»», ««key2:» «2»»»»)»
             """

    assert ~S"""
           for x <- [1, 2, 3], y <- [4, 5, 6] do
             x + y
           end
           """
           |> mark_ranges() ==
             ~S"""
             ««for» «««x» «<-» «[««1», «2», «3»»]»», ««y» «<-» «[««4», «5», «6»»]»»» ««do»
               ««x» «+» «y»»
             «end»»»
             """
  end

  test "comments" do
    assert ~S"""
           # Line 1
           """
           |> mark_ranges() ==
             ~S"""
             «# Line 1»
             """

    assert ~S"""
           # Line 1
           # Line 2
           """
           |> mark_ranges() ==
             ~S"""
             ««# Line 1»
             «# Line 2»»
             """

    assert ~S"""
           # Line 1
           # Line 2

           # Line 3
           # Line 4
           """
           |> mark_ranges() ==
             ~S"""
             «««# Line 1»
             «# Line 2»»

             ««# Line 3»
             «# Line 4»»»
             """

    assert ~S"""
           # Line 1
           true
           # Line 2
           """
           |> mark_ranges() ==
             ~S"""
             ««# Line 1»
             «true»
             «# Line 2»»
             """

    assert ~S"""
           # Line 1
           true
           true
           # Line 2
           """
           |> mark_ranges() ==
             ~S"""
             ««# Line 1»
             «true»
             «true»
             «# Line 2»»
             """

    assert ~S"""
           [ 1
             # Line 1
           ]
           """
           |> mark_ranges() ==
             ~S"""
             «[ ««1»
               «# Line 1»»
             ]»
             """

    assert ~S"""
           [
             # Line 1
             1,
             # Line 2
             2
             # Line 3
           ]
           """
           |> mark_ranges() ==
             ~S"""
             «[
               ««# Line 1»
               «1»,
               «# Line 2»
               «2»
               «# Line 3»»
             ]»
             """

    assert ~S"""
           [
             # Line 1
           ]
           """
           |> mark_ranges() ==
             ~S"""
             «[
               «# Line 1»
             ]»
             """

    assert ~S"""
           [
             # Line 1
             # Line 2
           ]
           """
           |> mark_ranges() ==
             ~S"""
             «[
               ««# Line 1»
               «# Line 2»»
             ]»
             """

    assert ~S"""
           [
             # Line 1

             # Line 2
           ]
           """
           |> mark_ranges() ==
             ~S"""
             «[
               ««# Line 1»

               «# Line 2»»
             ]»
             """

    assert ~S"""
           (
             # Line 1
             1
             # Line 2
             2
             # Line 3
           )
           """
           |> mark_ranges() ==
             ~S"""
             «(
               ««# Line 1»
               «1»
               «# Line 2»
               «2»
               «# Line 3»»
             )»
             """

    assert ~S"""
           (
             # Line 1
           )
           """
           |> mark_ranges() ==
             ~S"""
             «(
               «# Line 1»
             )»
             """

    assert ~S"""
           (
             # Line 1
             # Line 2
           )
           """
           |> mark_ranges() ==
             ~S"""
             «(
               ««# Line 1»
               «# Line 2»»
             )»
             """

    assert ~S"""
           (
             # Line 1
             1
             # Line 2
           )
           """
           |> mark_ranges() ==
             ~S"""
             «(
               ««# Line 1»
               «1»
               «# Line 2»»
             )»
             """

    assert ~S"""
           (
             # Line 1
             (
               x
             )
           )
           """
           |> mark_ranges() ==
             ~S"""
             «(
               ««# Line 1»
               «(
                 «x»
               )»»
             )»
             """

    assert ~S"""
           foo(
             # Line 1
             1,
             # Line 2
             2
             # Line 3
           )
           """
           |> mark_ranges() ==
             ~S"""
             ««foo»(
               ««# Line 1»
               «1»,
               «# Line 2»
               «2»
               «# Line 3»»
             )»
             """

    assert ~S"""
           Foo.foo(
             # Line 1
             1,
             # Line 2
             2
             # Line 3
           )
           """
           |> mark_ranges() ==
             ~S"""
             «««Foo»«.»«foo»»(
               ««# Line 1»
               «1»,
               «# Line 2»
               «2»
               «# Line 3»»
             )»
             """

    assert ~S"""
           unquote(foo)(
             # Line 1
             1,
             # Line 2
             2
             # Line 3
           )
           """
           |> mark_ranges() ==
             ~S"""
             «««unquote»(«foo»)»(
               ««# Line 1»
               «1»,
               «# Line 2»
               «2»
               «# Line 3»»
             )»
             """

    assert ~S"""
           fn ->
             # Line 1
           end
           """
           |> mark_ranges() ==
             ~S"""
             ««fn» ««->»
               «# Line 1»»
             «end»»
             """

    assert ~S"""
           fn x ->
             # Line 1
             x
           end
           """
           |> mark_ranges() ==
             ~S"""
             ««fn» ««x» «->»
               ««# Line 1»
               «x»»»
             «end»»
             """

    assert ~S"""
           fn x ->
             # Line 1
             x
             y
           end
           """
           |> mark_ranges() ==
             ~S"""
             ««fn» ««x» «->»
               ««# Line 1»
               «x»
               «y»»»
             «end»»
             """

    assert ~S"""
           fn
             # Line 1
             x -> x
             # Line 2
             y -> y
           end
           """
           |> mark_ranges() ==
             ~S"""
             ««fn»
               ««# Line 1»
               ««x» «->» «x»»
               «# Line 2»
               ««y» «->» «y»»»
             «end»»
             """

    assert ~S"""
           # Line 1
           1 + 2
           """
           |> mark_ranges() ==
             ~S"""
             ««# Line 1»
             ««1» «+» «2»»»
             """

    assert ~S"""
           if true do
             # Line 1

             # Line 2
           end
           """
           |> mark_ranges() ==
             ~S"""
             ««if» «true» ««do»
               ««# Line 1»

               «# Line 2»»
             «end»»»
             """

    assert ~S"""
           if true do
             # Line 1
             true
             # Line 2
           else
             # Line 3
             true
             # Line 4
           end
           """
           |> mark_ranges() ==
             ~S"""
             ««if» «true» ««do»
               ««# Line 1»
               «true»
               «# Line 2»»
             ««else»
               ««# Line 3»
               «true»
               «# Line 4»»»
             «end»»»
             """

    assert ~S"""
           ~s'''
           hello
           #{
             # Line 1
             x
             y
             # Line 2
           }
           welcome
           '''
           """
           |> mark_ranges() ==
             ~S"""
             «~s'''«
             hello
             «#{
               ««# Line 1»
               «x»
               «y»
               «# Line 2»»
             }»
             welcome
             »'''»
             """
  end

  defp mark_ranges(code) do
    ranges = AST.ranges(code)
    mark_ranges(code, ranges)
  end

  # Adds range markers to the given string.
  defp mark_ranges(string, ranges) do
    # If a closing and an opening marks conflict, we prioritise
    # the closing one, because we don't expect empty ranges, so
    # «» should never appear, but »« may
    marks =
      ranges
      |> Enum.flat_map(fn {from, to} -> [{from, 1, "«"}, {to, -1, "»"}] end)
      |> Enum.sort()

    mark_ranges(string, {1, 1}, marks, "")
  end

  defp mark_ranges(string, location, [{location, _priority, mark} | marks], acc) do
    mark_ranges(string, location, marks, <<acc::binary, mark::binary>>)
  end

  defp mark_ranges("", _location, _ranges, acc), do: acc

  defp mark_ranges(string, {line, column}, marks, acc) do
    {grapheme, string} = String.next_grapheme(string)
    acc = <<acc::binary, grapheme::binary>>

    if grapheme =~ "\n" do
      mark_ranges(string, {line + 1, 1}, marks, acc)
    else
      mark_ranges(string, {line, column + 1}, marks, acc)
    end
  end
end
