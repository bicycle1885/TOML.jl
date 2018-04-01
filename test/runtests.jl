using TOML: Token
import TOML
using Test

scan = TOML.scan
@time scan("\"foo\"")  # measure compile time
@test scan("\"foo\"") == :basic_string
@test scan("'foo'") == :literal_string
@test scan("123") == :integer
@test scan("123.0") == :float
@test scan("true") == :boolean
@test scan("1979-05-27T00:32:00-07:00") == :datetime
@test scan("abracadabra") == :none

function alltokens(str)
    stream = TOML.StreamReader(IOBuffer(str))
    tokens = TOML.Token[]
    while (t = TOML.parsetoken(stream)).kind != :eof
        push!(tokens, t)
    end
    return tokens
end

tokens = alltokens("")
@test tokens == Token[]

tokens = alltokens("  ")
@test tokens == [Token(:whitespace, "  ")]

tokens = alltokens("\r\n")
@test tokens == [ Token(:newline, "\r\n") ]

tokens = alltokens("""# comment\n""")
@test tokens == [
    Token(:comment, "# comment"),
    Token(:newline, "\n"),
]

tokens = alltokens("""
foo=100
""")
@test tokens == [
    Token(:bare_key, "foo"),
    Token(:equal, "="),
    Token(:integer, "100"),
    Token(:newline, "\n"),
]

tokens = alltokens("""
foo=3.14
""")
@test tokens == [
    Token(:bare_key, "foo"),
    Token(:equal, "="),
    Token(:float, "3.14"),
    Token(:newline, "\n"),
]

tokens = alltokens("""
foo=6.022e23
""")
@test tokens == [
    Token(:bare_key, "foo"),
    Token(:equal, "="),
    Token(:float, "6.022e23"),
    Token(:newline, "\n"),
]

tokens = alltokens("""
foo=true
bar=false
""")
@test tokens == [
    Token(:bare_key, "foo"),
    Token(:equal, "="),
    Token(:boolean, "true"),
    Token(:newline, "\n"),
    Token(:bare_key, "bar"),
    Token(:equal, "="),
    Token(:boolean, "false"),
    Token(:newline, "\n"),
]

tokens = alltokens("""
x = [1,2]
""")
@test tokens == [
    Token(:bare_key, "x"),
    Token(:whitespace, " "),
    Token(:equal, "="),
    Token(:whitespace, " "),
    Token(:inline_array_begin, ""),
    Token(:single_bracket_left, "["),
    Token(:integer, "1"),
    Token(:comma, ","),
    Token(:integer, "2"),
    Token(:single_bracket_right, "]"),
    Token(:inline_array_end, ""),
    Token(:newline, "\n"),
]

tokens = alltokens("""
x = [1,2,]
""")
@test tokens == [
    Token(:bare_key, "x"),
    Token(:whitespace, " "),
    Token(:equal, "="),
    Token(:whitespace, " "),
    Token(:inline_array_begin, ""),
    Token(:single_bracket_left, "["),
    Token(:integer, "1"),
    Token(:comma, ","),
    Token(:integer, "2"),
    Token(:comma, ","),
    Token(:single_bracket_right, "]"),
    Token(:inline_array_end, ""),
    Token(:newline, "\n"),
]

tokens = alltokens("""
x = [
    1,
    2,
]
""")
@test tokens == [
    Token(:bare_key, "x"),
    Token(:whitespace, " "),
    Token(:equal, "="),
    Token(:whitespace, " "),
    Token(:inline_array_begin, ""),
    Token(:single_bracket_left, "["),
    Token(:newline, "\n"),
    Token(:whitespace, "    "),
    Token(:integer, "1"),
    Token(:comma, ","),
    Token(:newline, "\n"),
    Token(:whitespace, "    "),
    Token(:integer, "2"),
    Token(:comma, ","),
    Token(:newline, "\n"),
    Token(:single_bracket_right, "]"),
    Token(:inline_array_end, ""),
    Token(:newline, "\n"),
]

tokens = alltokens("""
x = [ [ 1, 2 ], [3, 4, 5] ]
""")
@test tokens == [
    Token(:bare_key, "x"),
    Token(:whitespace, " "),
    Token(:equal, "="),
    Token(:whitespace, " "),
    Token(:inline_array_begin, ""),
    Token(:single_bracket_left, "["),
    Token(:whitespace, " "),
    Token(:inline_array_begin, ""),
    Token(:single_bracket_left, "["),
    Token(:whitespace, " "),
    Token(:integer, "1"),
    Token(:comma, ","),
    Token(:whitespace, " "),
    Token(:integer, "2"),
    Token(:whitespace, " "),
    Token(:single_bracket_right, "]"),
    Token(:inline_array_end, ""),
    Token(:comma, ","),
    Token(:whitespace, " "),
    Token(:inline_array_begin, ""),
    Token(:single_bracket_left, "["),
    Token(:integer, "3"),
    Token(:comma, ","),
    Token(:whitespace, " "),
    Token(:integer, "4"),
    Token(:comma, ","),
    Token(:whitespace, " "),
    Token(:integer, "5"),
    Token(:single_bracket_right, "]"),
    Token(:inline_array_end, ""),
    Token(:whitespace, " "),
    Token(:single_bracket_right, "]"),
    Token(:inline_array_end, ""),
    Token(:newline, "\n"),
]

tokens = alltokens("""
foo = { hoge = 100 }
""")
@test tokens == [
    Token(:bare_key, "foo"),
    Token(:whitespace, " "),
    Token(:equal, "="),
    Token(:whitespace, " "),
    Token(:inline_table_begin, ""),
    Token(:curly_brace_left, "{"),
    Token(:whitespace, " "),
    Token(:bare_key, "hoge"),
    Token(:whitespace, " "),
    Token(:equal, "="),
    Token(:whitespace, " "),
    Token(:integer, "100"),
    Token(:whitespace, " "),
    Token(:curly_brace_right, "}"),
    Token(:inline_table_end, ""),
    Token(:newline, "\n"),
]

tokens = alltokens("""
foo={hoge=100}
""")
@test tokens == [
 TOML.Token(:bare_key, "foo"),
 TOML.Token(:equal, "="),
 TOML.Token(:inline_table_begin, ""),
 TOML.Token(:curly_brace_left, "{"),
 TOML.Token(:bare_key, "hoge"),
 TOML.Token(:equal, "="),
 TOML.Token(:integer, "100"),
 TOML.Token(:curly_brace_right, "}"),
 Token(:inline_table_end, ""),
 TOML.Token(:newline, "\n"),
]

tokens = alltokens("""
name = { first = "Tom", last = "Preston-Werner" }
""")
@test tokens == [
     TOML.Token(:bare_key, "name"),
     TOML.Token(:whitespace, " "),
     TOML.Token(:equal, "="),
     TOML.Token(:whitespace, " "),
     TOML.Token(:inline_table_begin, ""),
     TOML.Token(:curly_brace_left, "{"),
     TOML.Token(:whitespace, " "),
     TOML.Token(:bare_key, "first"),
     TOML.Token(:whitespace, " "),
     TOML.Token(:equal, "="),
     TOML.Token(:whitespace, " "),
     TOML.Token(:basic_string, "\"Tom\""),
     TOML.Token(:comma, ","),
     TOML.Token(:whitespace, " "),
     TOML.Token(:bare_key, "last"),
     TOML.Token(:whitespace, " "),
     TOML.Token(:equal, "="),
     TOML.Token(:whitespace, " "),
     TOML.Token(:basic_string, "\"Preston-Werner\""),
     TOML.Token(:whitespace, " "),
     TOML.Token(:curly_brace_right, "}"),
     TOML.Token(:inline_table_end, ""),
     TOML.Token(:newline, "\n"),
]

tokens = alltokens("""[foo]\n""")
@test tokens == [
    Token(:table_begin, ""),
    Token(:single_bracket_left, "["),
    Token(:bare_key, "foo"),
    Token(:single_bracket_right, "]"),
    Token(:table_end, ""),
    Token(:newline, "\n"),
]

tokens = alltokens("""[foo.bar]\n""")
@test tokens == [
    Token(:table_begin, ""),
    Token(:single_bracket_left, "["),
    Token(:bare_key, "foo"),
    Token(:dot, "."),
    Token(:bare_key, "bar"),
    Token(:single_bracket_right, "]"),
    Token(:table_end, ""),
    Token(:newline, "\n"),
]

tokens = alltokens("""[[foo]]\n""")
@test tokens == [
    Token(:array_begin, ""),
    Token(:double_brackets_left, "[["),
    Token(:bare_key, "foo"),
    Token(:double_brackets_right, "]]"),
    Token(:array_end, ""),
    Token(:newline, "\n"),
]

tokens = alltokens("""
"127.0.0.1" = "value"
""")
@test tokens == [
    Token(:quoted_key, "\"127.0.0.1\""),
    Token(:whitespace, " "),
    Token(:equal, "="),
    Token(:whitespace, " "),
    Token(:basic_string, "\"value\""),
    Token(:newline, "\n"),
]

tokens = alltokens("""
[dog."tater.man"]
""")
@test tokens == [
    Token(:table_begin, ""),
    Token(:single_bracket_left, "["),
    Token(:bare_key, "dog"),
    Token(:dot, "."),
    Token(:quoted_key, "\"tater.man\""),
    Token(:single_bracket_right, "]"),
    Token(:table_end, ""),
    Token(:newline, "\n"),
]

