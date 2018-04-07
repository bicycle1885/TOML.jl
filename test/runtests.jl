using TOML: Token
import TOML
using Test
using Dates

# Use a small buffer size to detect buffering bugs.
TOML.INIT_BUFFER_SIZE[] = 4

@testset "Tokenizer" begin
    for (text, expectvalue, token) in
        [
            # simple tokens
            ("",        false, TOML.TOKEN_EOF),
            (" ",       false, TOML.TOKEN_WHITESPACE_SPACE),
            ("\t",      false, TOML.TOKEN_WHITESPACE_TAB),
            ("\n",      false, TOML.TOKEN_NEWLINE_LF),
            ("\r\n",    false, TOML.TOKEN_NEWLINE_CRLF),
            ("# a b",   false, TOML.Token(:comment, "# a b")),
            ("=",       false, TOML.TOKEN_EQUAL),
            (".",       false, TOML.TOKEN_DOT),
            (",",       false, TOML.TOKEN_COMMA),
            ("{",       false, TOML.TOKEN_CURLY_BRACE_LEFT),
            ("}",       false, TOML.TOKEN_CURLY_BRACE_RIGHT),
            # tokens depending on the `expectvalue` parameter
            ("100",     false, TOML.Token(:bare_key, "100")),
            ("100",     true,  TOML.Token(:decimal, "100")),
            ("true",    false, TOML.Token(:bare_key, "true")),
            ("true",    true,  TOML.Token(:boolean, "true")),
            ("false",   false, TOML.Token(:bare_key, "false")),
            ("false",   true,  TOML.Token(:boolean, "false")),
            ("\"key\"", false, TOML.Token(:quoted_key, "\"key\"")),
            ("\"key\"", true,  TOML.Token(:basic_string, "\"key\"")),
            ("'key'",   false, TOML.Token(:quoted_key, "'key'")),
            ("'key'",   true,  TOML.Token(:literal_string, "'key'")),
            ("[[",      false, TOML.TOKEN_DOUBLE_BRACKETS_LEFT),
            ("[[",      true,  TOML.TOKEN_SINGLE_BRACKET_LEFT),
            ("]]",      false, TOML.TOKEN_DOUBLE_BRACKETS_RIGHT),
            ("]]",      true,  TOML.TOKEN_SINGLE_BRACKET_RIGHT),
            # unknown tokens (will result in parse error)
            ("!",       false, TOML.Token(:unknown, "!")),
            ("\rX",     false, TOML.Token(:unknown, "\r")),
            ("\"X",     false, TOML.Token(:unknown, "\"")),
            ("'X",      false, TOML.Token(:unknown, "'")),
        ]
        tokenizer = TOML.Tokenizer(IOBuffer(text))
        @test TOML.readtoken(tokenizer, expectvalue=expectvalue) == token
    end

    tokenizer = TOML.Tokenizer(IOBuffer("100"))
    @test TOML.peektoken(tokenizer, expectvalue=false) == TOML.Token(:bare_key, "100")
    @test TOML.peektoken(tokenizer, expectvalue=true)  == TOML.Token(:decimal, "100")
    @test TOML.peektoken(tokenizer, expectvalue=false) == TOML.Token(:bare_key, "100")
    @test TOML.peektoken(tokenizer, expectvalue=true)  == TOML.Token(:decimal, "100")
    @test TOML.readtoken(tokenizer, expectvalue=false) == TOML.Token(:bare_key, "100")
    @test TOML.readtoken(tokenizer, expectvalue=false) == TOML.TOKEN_EOF
end

# bare key
@test TOML.keyname(Token(:bare_key, "foo")) === "foo"
@test TOML.keyname(Token(:bare_key, "foo-bar")) === "foo-bar"

# quoted key
@test TOML.keyname(Token(:quoted_key, "\"foo\"")) === "foo"
@test TOML.keyname(Token(:quoted_key, "'foo'")) === "foo"
@test TOML.keyname(Token(:quoted_key, "\"\"")) === ""
@test TOML.keyname(Token(:quoted_key, "''")) === ""
@test TOML.keyname(Token(:quoted_key, "\"foo キー\"")) === "foo キー"
@test TOML.keyname(Token(:quoted_key, "'foo キー'")) === "foo キー"

@test_throws ArgumentError("not a key token") TOML.keyname(Token(:decimal, "1234"))

# decimal
@test TOML.value(Token(:decimal, "1234567890")) === 1234567890
@test TOML.value(Token(:decimal, "-1234")) === -1234
@test TOML.value(Token(:decimal, "-1_23_4")) === -1234

# binary
@test TOML.value(Token(:binary, "0b01")) === UInt(0b01)
@test TOML.value(Token(:binary, "0b0_1")) === UInt(0b01)

# octal
@test TOML.value(Token(:octal, "0o01234567")) === UInt(0o01234567)
@test TOML.value(Token(:octal, "0o0123_45_67")) === UInt(0o01234567)

# hexadecimal
@test TOML.value(Token(:hexadecimal, "0x0123456789ABCDEF")) === UInt(0x0123456789ABCDEF)
@test TOML.value(Token(:hexadecimal, "0x0123456789abcdef")) === UInt(0x0123456789abcdef)
@test TOML.value(Token(:hexadecimal, "0x0123_456789ab_cdef")) === UInt(0x0123456789abcdef)

# float
@test TOML.value(Token(:float, "1.23")) === 1.23
@test TOML.value(Token(:float, "1e-2")) === 1e-2
@test TOML.value(Token(:float, "inf"))  === Inf
@test TOML.value(Token(:float, "-inf")) === -Inf
@test TOML.value(Token(:float, "+inf")) === Inf
@test TOML.value(Token(:float, "nan"))  === NaN
@test TOML.value(Token(:float, "-nan")) === -NaN
@test TOML.value(Token(:float, "+nan")) === NaN
@test TOML.value(Token(:float, "9_224_617.445_991_228_313")) === 9224617.445991228313

# boolean
@test TOML.value(Token(:boolean, "true"))  === true
@test TOML.value(Token(:boolean, "false")) === false

# basic string
@test TOML.value(Token(:basic_string, "\"\"")) === ""
@test TOML.value(Token(:basic_string, "\"foobar\"")) === "foobar"
@test TOML.value(Token(:basic_string, "\"αβγあいう\"")) === "αβγあいう"
@test TOML.value(Token(:basic_string, "\"escaping: \\\" \\b \\t \\n \\f \\r \\\" \\\\ \"")) === "escaping: \" \b \t \n \f \r \" \\ "
@test TOML.value(Token(:basic_string, "\"unicode: \\u3042\"")) === "unicode: あ"
@test TOML.value(Token(:basic_string, "\"unicode: \\U00003042\"")) === "unicode: あ"

# multiline basic string
@test TOML.value(Token(:multiline_basic_string, "\"\"\"\"\"\"")) === ""
@test TOML.value(Token(:multiline_basic_string, "\"\"\"foobar\"\"\"")) === "foobar"
@test TOML.value(Token(:multiline_basic_string, "\"\"\"αβγあいう\"\"\"")) === "αβγあいう"
@test TOML.value(Token(:multiline_basic_string,
"""\"\"\"
multi
-line
文章
\"\"\"""")) === "multi\n-line\n文章\n"
@test TOML.value(Token(:multiline_basic_string,
"""\"\"\"
line 1\r
line 2\r
\"\"\"""")) === "line 1\nline 2\n"
@test TOML.value(Token(:multiline_basic_string,
"""\"\"\"
foo\\

     bar
\"\"\"""")) === "foobar\n"

# literal string
@test TOML.value(Token(:literal_string, "''")) === ""
@test TOML.value(Token(:literal_string, "'αβγあいう'")) === "αβγあいう"
@test TOML.value(Token(:literal_string, "'C:\\Users\\Windows\\Path'")) === raw"C:\Users\Windows\Path"

# multiline literal string
@test TOML.value(Token(:multiline_literal_string, "''''''")) === ""
@test TOML.value(Token(:multiline_literal_string, "'''αβγあいう'''")) === "αβγあいう"
@test TOML.value(Token(:multiline_literal_string, "'''C:\\Users\\Windows\\Path'''")) === raw"C:\Users\Windows\Path"
@test TOML.value(Token(:multiline_literal_string,
"'''
line 1\r
line 2\r
'''")) === "line 1\nline 2\n"
@test TOML.value(Token(:multiline_literal_string,
"'''
foo\\

     bar
'''")) === "foo\\\n\n     bar\n"

# datetime
@test TOML.value(Token(:datetime, "1979-05-27T07:32:00Z")) == (DateTime(1979, 5, 27, 7, 32, 00), "Z")
@test TOML.value(Token(:datetime, "1979-05-27 07:32:00Z")) == (DateTime(1979, 5, 27, 7, 32, 00), "Z")
@test TOML.value(Token(:datetime, "1979-05-27T00:32:00-07:00")) == (DateTime(1979, 5, 27, 00, 32, 00), "-07:00")
@test TOML.value(Token(:datetime, "1979-05-27T00:32:00.999-07:00")) == (DateTime(1979, 5, 27, 00, 32, 00, 999), "-07:00")

@test_throws ArgumentError("not a value token: Token(:bare_key, \"foo\")") TOML.value(Token(:bare_key, "foo"))

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

@test_throws ErrorException("invalid UTF-8 sequence") alltokens(String([0x80]))

tokens = alltokens("")
@test tokens == Token[]

tokens = alltokens("  ")
@test tokens == [Token(:whitespace, "  ")]

tokens = alltokens("\t")
@test tokens == [Token(:whitespace, "\t")]

tokens = alltokens("\r\n")
@test tokens == [ Token(:newline, "\r\n") ]

tokens = alltokens("""# comment\n""")
@test tokens == [
    Token(:comment, "# comment"),
    Token(:newline, "\n"),
]

tokens = alltokens("""
foo = "text"
""")
@test tokens == [
 TOML.Token(:bare_key, "foo"),
 TOML.Token(:whitespace, " "),
 TOML.Token(:equal, "="),
 TOML.Token(:whitespace, " "),
 TOML.Token(:basic_string, "\"text\""),
 TOML.Token(:newline, "\n"),
]

tokens = alltokens("""
foo = \"\"\"
"text1"
""text2""
\"\"\"
""")
@test tokens == [
 TOML.Token(:bare_key, "foo"),
 TOML.Token(:whitespace, " "),
 TOML.Token(:equal, "="),
 TOML.Token(:whitespace, " "),
 TOML.Token(:multiline_basic_string, "\"\"\"\n\"text1\"\n\"\"text2\"\"\n\"\"\""),
 TOML.Token(:newline, "\n"),
]

tokens = alltokens("""
foo = 'text'
""")
@test tokens == [
 TOML.Token(:bare_key, "foo"),
 TOML.Token(:whitespace, " "),
 TOML.Token(:equal, "="),
 TOML.Token(:whitespace, " "),
 TOML.Token(:literal_string, "'text'"),
 TOML.Token(:newline, "\n"),
]

tokens = TOML.debug("""
foo = '''
'text'
''text2''
'''
""")
@test tokens == [
 TOML.Token(:bare_key, "foo"),
 TOML.Token(:whitespace, " "),
 TOML.Token(:equal, "="),
 TOML.Token(:whitespace, " "),
 TOML.Token(:multiline_literal_string, "'''\n'text'\n''text2''\n'''"),
 TOML.Token(:newline, "\n"),
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
foo=0x0123456789ABCDEF
""")
@test tokens == [
    Token(:bare_key, "foo"),
    Token(:equal, "="),
    Token(:hexadecimal, "0x0123456789ABCDEF"),
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

tokens = alltokens("x={foo={x=10}, bar={y=20},}")
@test tokens == [
 TOML.Token(:bare_key, "x"),
 TOML.Token(:equal, "="),
 TOML.Token(:inline_table_begin, ""),
 TOML.Token(:curly_brace_left, "{"),
 TOML.Token(:bare_key, "foo"),
 TOML.Token(:equal, "="),
 TOML.Token(:inline_table_begin, ""),
 TOML.Token(:curly_brace_left, "{"),
 TOML.Token(:bare_key, "x"),
 TOML.Token(:equal, "="),
 TOML.Token(:decimal, "10"),
 TOML.Token(:curly_brace_right, "}"),
 TOML.Token(:inline_table_end, ""),
 TOML.Token(:comma, ","),
 TOML.Token(:whitespace, " "),
 TOML.Token(:bare_key, "bar"),
 TOML.Token(:equal, "="),
 TOML.Token(:inline_table_begin, ""),
 TOML.Token(:curly_brace_left, "{"),
 TOML.Token(:bare_key, "y"),
 TOML.Token(:equal, "="),
 TOML.Token(:decimal, "20"),
 TOML.Token(:curly_brace_right, "}"),
 TOML.Token(:inline_table_end, ""),
 TOML.Token(:comma, ","),
 TOML.Token(:curly_brace_right, "}"),
 TOML.Token(:inline_table_end, ""),
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
@test_throws TOML.ParseError("unexpected '\0' at line 1") alltokens("# \0")
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

data = TOML.parse("sushi = \"🍣\"\nbeer = \"🍺\"")
@test data == Dict("sushi" => "🍣", "beer" => "🍺")

data = TOML.parse("x = [1]\ny = [1,2,3]\nz = []")
@test data == Dict("x" => [1], "y" => [1,2,3], "z" => [])
@test data["x"] isa Vector{Int}
@test data["y"] isa Vector{Int}
@test data["z"] isa Vector{Any}

data = TOML.parse("x = [[1,2,3], [1,2]]\ny = [[1,2]]\nz = [[[]]]")
@test data == Dict("x" => [[1,2,3], [1,2]], "y" => [[1,2]], "z" => [[[]]])
@test data["x"] isa Vector{Vector}

data = TOML.parse("name = { first = \"Tom\", last = \"Preston-Werner\" }")
@test data == Dict("name" => Dict("first" => "Tom", "last" => "Preston-Werner"))

data = TOML.parse("x = {foo = 10, bar = { a = 1, b = 2 }, baz = {}}")
@test data == Dict("x" => Dict("foo" => 10, "bar" => Dict("a" => 1, "b" => 2), "baz" => Dict()))

data = TOML.parse(
"""
key1 = 0

[foo]
key1 = 1
key2 = 2

[bar]
key1 = 10
key2 = 20

[foo.bar.baz]
qux = 100
""")
@test data == Dict(
    "key1" => 0,
    "foo" => Dict("key1" => 1, "key2" => 2, "bar" => Dict("baz" => Dict("qux" => 100))),
    "bar" => Dict("key1" => 10, "key2" => 20))

data = TOML.parse(
"""
[[foo]]
x = 1
y = 2

[[foo]]

[[foo]]
x = 10
y = 20
z = 30

[[bar.baz]]
qux = 100
""")
@test data == Dict(
    "foo" => [
        Dict("x" => 1, "y" => 2),
        Dict(),
        Dict("x" => 10, "y" => 20, "z" => 30),
    ],
    "bar" => Dict("baz" => [Dict("qux" => 100)]))
@test data["foo"] isa Vector{Dict{String,Any}}

data = TOML.parse(
"""
[[fruit]]
  name = "apple"

  [fruit.physical]
    color = "red"
    shape = "round"

  [[fruit.variety]]
    name = "red delicious"

  [[fruit.variety]]
    name = "granny smith"

[[fruit]]
  name = "banana"

  [[fruit.variety]]
    name = "plantain"
""")
@test data == Dict(
    "fruit" => [
        Dict(
            "name" => "apple",
            "physical" => Dict("color" => "red", "shape" => "round"),
            "variety" => [Dict("name" => "red delicious"), Dict("name" => "granny smith")]),
        Dict(
             "name" => "banana",
             "variety" => [Dict("name" => "plantain")])
    ])

data = TOML.parse(IOBuffer(
"""
x = 100
"""))
@test data == Dict("x" => 100)

data = TOML.parse("""
[a.b]
c = 1

[a]
d = 2
""")
@test data == Dict("a" => Dict("b" => Dict("c" => 1), "d" => 2))

@test_throws TOML.ParseError("mixed array types at line 1") TOML.parse("x = [1, 1.0]")
@test_throws TOML.ParseError("mixed array types at line 1") TOML.parse("x = [[1,2], 3]")
@test_throws TOML.ParseError("found a duplicated definition at line 4") TOML.parse(
"""
[a]
b = 1

[a]
c = 2
""")
@test_throws TOML.ParseError("found a duplicated definition at line 4") TOML.parse(
"""
[a]
b = 1

[a.b]
c = 2
""")
