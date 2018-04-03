using TOML: Token
import TOML
using Test

# decimal
@test TOML.value(Token(:decimal, "1234567890")) === 1234567890
@test TOML.value(Token(:decimal, "-1234")) === -1234

# binary
@test TOML.value(Token(:binary, "0b01")) === UInt(0b01)

# octal
@test TOML.value(Token(:octal, "0o01234567")) === UInt(0o01234567)

# hexadecimal
@test TOML.value(Token(:hexadecimal, "0x0123456789ABCDEF")) === UInt(0x0123456789ABCDEF)
@test TOML.value(Token(:hexadecimal, "0x0123456789abcdef")) === UInt(0x0123456789abcdef)

# float
@test TOML.value(Token(:float, "1.23")) === 1.23
@test TOML.value(Token(:float, "1e-2")) === 1e-2
@test TOML.value(Token(:float, "inf"))  === Inf
@test TOML.value(Token(:float, "-inf")) === -Inf
@test TOML.value(Token(:float, "+inf")) === Inf
@test TOML.value(Token(:float, "nan"))  === NaN
@test TOML.value(Token(:float, "-nan")) === -NaN
@test TOML.value(Token(:float, "+nan")) === NaN

# boolean
@test TOML.value(Token(:boolean, "true"))  === true
@test TOML.value(Token(:boolean, "false")) === false

@test TOML.scanvalue(IOBuffer("\"foo\""), TOML.Buffer()) == (:basic_string, 5)
@test TOML.scanvalue(IOBuffer("'foo'"), TOML.Buffer()) == (:literal_string, 5)
@test TOML.scanvalue(IOBuffer("123"), TOML.Buffer()) == (:decimal, 3)
@test TOML.scanvalue(IOBuffer("123.0"), TOML.Buffer()) == (:float, 5)
@test TOML.scanvalue(IOBuffer("true"), TOML.Buffer()) == (:boolean, 4)
@test TOML.scanvalue(IOBuffer("1979-05-27T00:32:00-07:00"), TOML.Buffer()) == (:datetime, 25)
@test TOML.scanvalue(IOBuffer("1979-05-27T07:32:00"), TOML.Buffer()) == (:local_datetime, 19)
@test TOML.scanvalue(IOBuffer("1979-05-27"), TOML.Buffer()) == (:local_date, 10)
@test TOML.scanvalue(IOBuffer("07:32:00"), TOML.Buffer()) == (:local_time, 8)
@test TOML.scanvalue(IOBuffer("abracadabra"), TOML.Buffer()) == (:novalue, 0)

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
    Token(:decimal, "100"),
    Token(:newline, "\n"),
]

tokens = alltokens("""
foo=0b11010110
""")
@test tokens == [
    Token(:bare_key, "foo"),
    Token(:equal, "="),
    Token(:binary, "0b11010110"),
    Token(:newline, "\n"),
]

tokens = alltokens("""
foo=0o1234567
""")
@test tokens == [
    Token(:bare_key, "foo"),
    Token(:equal, "="),
    Token(:octal, "0o1234567"),
    Token(:newline, "\n"),
]

tokens = alltokens("""
foo=0x0123456789abcdef
""")
@test tokens == [
    Token(:bare_key, "foo"),
    Token(:equal, "="),
    Token(:hexadecimal, "0x0123456789abcdef"),
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
foo=inf
""")
@test tokens == [
    Token(:bare_key, "foo"),
    Token(:equal, "="),
    Token(:float, "inf"),
    Token(:newline, "\n"),
]

tokens = alltokens("""
foo=nan
""")
@test tokens == [
    Token(:bare_key, "foo"),
    Token(:equal, "="),
    Token(:float, "nan"),
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
"foo"=100
""")
@test tokens == [
 TOML.Token(:quoted_key, "\"foo\""),
 TOML.Token(:equal, "="),
 TOML.Token(:decimal, "100"),
 TOML.Token(:newline, "\n"),
]

tokens = alltokens("""
'foo'=100
""")
@test tokens == [
 TOML.Token(:quoted_key, "'foo'"),
 TOML.Token(:equal, "="),
 TOML.Token(:decimal, "100"),
 TOML.Token(:newline, "\n"),
]

tokens = alltokens("""
foo.bar=100
""") == [
 TOML.Token(:bare_key, "foo"),
 TOML.Token(:dot, "."),
 TOML.Token(:bare_key, "bar"),
 TOML.Token(:equal, "="),
 TOML.Token(:decimal, "10"),
]

tokens = alltokens("""
foo .  bar=100
""") == [
 TOML.Token(:bare_key, "foo"),
 TOML.Token(:whitespace, " "),
 TOML.Token(:dot, "."),
 TOML.Token(:whitespace, "  "),
 TOML.Token(:bare_key, "bar"),
 TOML.Token(:equal, "="),
 TOML.Token(:decimal, "10"),
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
    Token(:decimal, "1"),
    Token(:comma, ","),
    Token(:decimal, "2"),
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
    Token(:decimal, "1"),
    Token(:comma, ","),
    Token(:decimal, "2"),
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
    Token(:decimal, "1"),
    Token(:comma, ","),
    Token(:newline, "\n"),
    Token(:whitespace, "    "),
    Token(:decimal, "2"),
    Token(:comma, ","),
    Token(:newline, "\n"),
    Token(:single_bracket_right, "]"),
    Token(:inline_array_end, ""),
    Token(:newline, "\n"),
]

tokens = alltokens("""
x = [
  1,
  2, # comment
]
""")
@test tokens == [
 TOML.Token(:bare_key, "x"),
 TOML.Token(:whitespace, " "),
 TOML.Token(:equal, "="),
 TOML.Token(:whitespace, " "),
 TOML.Token(:inline_array_begin, ""),
 TOML.Token(:single_bracket_left, "["),
 TOML.Token(:newline, "\n"),
 TOML.Token(:whitespace, "  "),
 TOML.Token(:decimal, "1"),
 TOML.Token(:comma, ","),
 TOML.Token(:newline, "\n"),
 TOML.Token(:whitespace, "  "),
 TOML.Token(:decimal, "2"),
 TOML.Token(:comma, ","),
 TOML.Token(:whitespace, " "),
 TOML.Token(:comment, "# comment"),
 TOML.Token(:newline, "\n"),
 TOML.Token(:single_bracket_right, "]"),
 TOML.Token(:inline_array_end, ""),
 TOML.Token(:newline, "\n"),
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
    Token(:decimal, "1"),
    Token(:comma, ","),
    Token(:whitespace, " "),
    Token(:decimal, "2"),
    Token(:whitespace, " "),
    Token(:single_bracket_right, "]"),
    Token(:inline_array_end, ""),
    Token(:comma, ","),
    Token(:whitespace, " "),
    Token(:inline_array_begin, ""),
    Token(:single_bracket_left, "["),
    Token(:decimal, "3"),
    Token(:comma, ","),
    Token(:whitespace, " "),
    Token(:decimal, "4"),
    Token(:comma, ","),
    Token(:whitespace, " "),
    Token(:decimal, "5"),
    Token(:single_bracket_right, "]"),
    Token(:inline_array_end, ""),
    Token(:whitespace, " "),
    Token(:single_bracket_right, "]"),
    Token(:inline_array_end, ""),
    Token(:newline, "\n"),
]

tokens = alltokens("x=[{foo=10}]")
@test tokens == [
 TOML.Token(:bare_key, "x"),
 TOML.Token(:equal, "="),
 TOML.Token(:inline_array_begin, ""),
 TOML.Token(:single_bracket_left, "["),
 TOML.Token(:inline_table_begin, ""),
 TOML.Token(:curly_brace_left, "{"),
 TOML.Token(:bare_key, "foo"),
 TOML.Token(:equal, "="),
 TOML.Token(:decimal, "10"),
 TOML.Token(:curly_brace_right, "}"),
 TOML.Token(:inline_table_end, ""),
 TOML.Token(:single_bracket_right, "]"),
 TOML.Token(:inline_array_end, ""),
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
    Token(:decimal, "100"),
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
 TOML.Token(:decimal, "100"),
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

tokens = alltokens("x={foo=[1,2]}")
@test tokens == [
 TOML.Token(:bare_key, "x"),
 TOML.Token(:equal, "="),
 TOML.Token(:inline_table_begin, ""),
 TOML.Token(:curly_brace_left, "{"),
 TOML.Token(:bare_key, "foo"),
 TOML.Token(:equal, "="),
 TOML.Token(:inline_array_begin, ""),
 TOML.Token(:single_bracket_left, "["),
 TOML.Token(:decimal, "1"),
 TOML.Token(:comma, ","),
 TOML.Token(:decimal, "2"),
 TOML.Token(:single_bracket_right, "]"),
 TOML.Token(:inline_array_end, ""),
 TOML.Token(:curly_brace_right, "}"),
 TOML.Token(:inline_table_end, ""),
]

tokens = alltokens("x={foo=[[10]]}")
@test tokens == [
 TOML.Token(:bare_key, "x"),
 TOML.Token(:equal, "="),
 TOML.Token(:inline_table_begin, ""),
 TOML.Token(:curly_brace_left, "{"),
 TOML.Token(:bare_key, "foo"),
 TOML.Token(:equal, "="),
 TOML.Token(:inline_array_begin, ""),
 TOML.Token(:single_bracket_left, "["),
 TOML.Token(:inline_array_begin, ""),
 TOML.Token(:single_bracket_left, "["),
 TOML.Token(:decimal, "10"),
 TOML.Token(:single_bracket_right, "]"),
 TOML.Token(:inline_array_end, ""),
 TOML.Token(:single_bracket_right, "]"),
 TOML.Token(:inline_array_end, ""),
 TOML.Token(:curly_brace_right, "}"),
 TOML.Token(:inline_table_end, ""),
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

@test_throws TOML.ParseError("unexpected '!' at line 1") alltokens("!")
@test_throws TOML.ParseError("unexpected '!' at line 3") alltokens("\n\n!")
@test_throws TOML.ParseError("unexpected end of file at line 1") alltokens("x")
@test_throws TOML.ParseError("unexpected end of file at line 1") alltokens("x=")
@test_throws TOML.ParseError("unexpected ',' at line 1") alltokens("x,")
@test_throws TOML.ParseError("invalid value format at line 1") alltokens("x = p")
@test_throws TOML.ParseError("invalid value format at line 1") alltokens("x = [,1]")
@test_throws TOML.ParseError("invalid value format at line 1") alltokens("x='foo")
@test_throws TOML.ParseError("unexpected newline at line 1") alltokens("x=\n10")
@test_throws TOML.ParseError("unexpected bare key 'bar' at line 1") alltokens("foo=100 bar=200")
@test_throws TOML.ParseError("unexpected ']' at line 1") alltokens("[]")
@test_throws TOML.ParseError("unexpected ']' at line 1") alltokens("[foo.]")
@test_throws TOML.ParseError("unexpected '=' at line 1") alltokens("[foo=]")
@test_throws TOML.ParseError("unexpected ']]' at line 1") alltokens("[foo]]")
@test_throws TOML.ParseError("unexpected ']' at line 1") alltokens("[[hoge]")
@test_throws TOML.ParseError("unexpected ']]' at line 1") alltokens("[[hoge.]]")
@test_throws TOML.ParseError("unexpected end of file at line 1") alltokens("[foo")
@test_throws TOML.ParseError("unexpected ']' at line 1") alltokens("x=[100]]")
@test_throws TOML.ParseError("unexpected end of file at line 1") alltokens("x=[100")
@test_throws TOML.ParseError("unexpected '}' at line 1") alltokens("x={foo}")
@test_throws TOML.ParseError("unexpected ',' at line 1") alltokens("x={,foo=100}")
@test_throws TOML.ParseError("unexpected '=' at line 1") alltokens("x={10.=10}")
@test_throws TOML.ParseError("unexpected newline at line 1") alltokens("x={\nfoo=100}")
@test_throws TOML.ParseError("line feed (LF) is expected after carriage return (CR) at line 1") alltokens("foo=100\r")
@test_throws TOML.ParseError("unexpected newline at line 11") alltokens(
"""
foo = '''
some
text
'''

bar = \"\"\"
some
text
\"\"\"

error =
""")

using Random
randutf8(n) = String(rand(['α', 'あ', '𐍈'], n))
srand(1234)
@test all(map(0:200) do n
    s = string("#", randutf8(n))
    alltokens(s) == [Token(:comment, s)]
end)

data = TOML.parse("")
@test data == Dict()

data = TOML.parse("foo = 100")
@test data == Dict("foo" => 100)

data = TOML.parse("foo = 100\nbar = 1.23")
@test data == Dict("foo" => 100, "bar" => 1.23)

#=
data = TOML.parse(
"""
name = "hi"

[foo]
bar = 1234
baz = 'aaa'
""")
@show data
=#
