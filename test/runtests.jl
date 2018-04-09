using TOML: Token
import TOML
using Test
using Dates

# Use a small buffer size to detect buffering bugs.
TOML.INIT_BUFFER_SIZE[] = 4

@testset "Token" begin
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
    @test TOML.value(Token(:multiline_literal_string, """
    '''
    line 1\r
    line 2\r
    '''""")) === "line 1\nline 2\n"
    @test TOML.value(Token(:multiline_literal_string, """
    '''
    foo\\

         bar
    '''""")) === "foo\\\n\n     bar\n"

    # datetime
    @test TOML.value(Token(:datetime, "1979-05-27T07:32:00Z")) == (DateTime(1979, 5, 27, 7, 32, 00), "Z")
    @test TOML.value(Token(:datetime, "1979-05-27 07:32:00Z")) == (DateTime(1979, 5, 27, 7, 32, 00), "Z")
    @test TOML.value(Token(:datetime, "1979-05-27T00:32:00-07:00")) == (DateTime(1979, 5, 27, 00, 32, 00), "-07:00")
    @test TOML.value(Token(:datetime, "1979-05-27T00:32:00.999-07:00")) == (DateTime(1979, 5, 27, 00, 32, 00, 999), "-07:00")

    @test_throws ArgumentError("not a value token: Token(:bare_key, \"foo\")") TOML.value(Token(:bare_key, "foo"))
end

@testset "Tokenizer" begin
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

    for (text, rhs, token) in
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
            # tokens depending on the `rhs` parameter
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
        @test TOML.readtoken(tokenizer, rhs=rhs) == token
    end

    tokenizer = TOML.Tokenizer(IOBuffer("100"))
    @test TOML.peektoken(tokenizer, rhs=false) == TOML.Token(:bare_key, "100")
    @test TOML.peektoken(tokenizer, rhs=true)  == TOML.Token(:decimal, "100")
    @test TOML.peektoken(tokenizer, rhs=false) == TOML.Token(:bare_key, "100")
    @test TOML.peektoken(tokenizer, rhs=true)  == TOML.Token(:decimal, "100")
    @test TOML.readtoken(tokenizer, rhs=false) == TOML.Token(:bare_key, "100")
    @test TOML.readtoken(tokenizer, rhs=false) == TOML.TOKEN_EOF
end

@testset "StreamReader" begin
    function tokens(str)
        stream = TOML.StreamReader(IOBuffer(str))
        ts = TOML.Token[]
        while (t = TOML.parsetoken(stream)).kind != :eof
            push!(ts, t)
        end
        return ts
    end

    @test_throws ErrorException("invalid UTF-8 sequence") tokens("\x80")

    @test tokens("") == TOML.Token[]
    @test tokens(" ") == [TOML.Token(:whitespace, " ")]
    @test tokens("  ") == [TOML.Token(:whitespace, "  ")]
    @test tokens("\t") == [TOML.Token(:whitespace, "\t")]
    @test tokens("\t  ") == [TOML.Token(:whitespace, "\t  ")]
    @test tokens("\n") == [TOML.Token(:newline, "\n")]
    @test tokens("\r\n") == [TOML.Token(:newline, "\r\n")]
    @test tokens("#comment") == [TOML.Token(:comment, "#comment")]
    @test tokens("#αあ𐍈") == [TOML.Token(:comment, "#αあ𐍈")]

    @test tokens("""
      # comment
    """) == [
        TOML.Token(:whitespace, "  "),
        TOML.Token(:comment, "# comment"),
        TOML.Token(:newline, "\n"),
    ]

    @test tokens("x=10") == [
        TOML.Token(:bare_key, "x"),
        TOML.Token(:equal, "="),
        TOML.Token(:decimal, "10"),
    ]

    @test tokens("x = 10") == [
        TOML.Token(:bare_key, "x"),
        TOML.Token(:whitespace, " "),
        TOML.Token(:equal, "="),
        TOML.Token(:whitespace, " "),
        TOML.Token(:decimal, "10"),
    ]

    @test tokens("x = 10.0") == [
        TOML.Token(:bare_key, "x"),
        TOML.Token(:whitespace, " "),
        TOML.Token(:equal, "="),
        TOML.Token(:whitespace, " "),
        TOML.Token(:float, "10.0"),
    ]

    @test tokens("x = 6.022e23") == [
        TOML.Token(:bare_key, "x"),
        TOML.Token(:whitespace, " "),
        TOML.Token(:equal, "="),
        TOML.Token(:whitespace, " "),
        TOML.Token(:float, "6.022e23"),
    ]

    @test tokens("x = inf") == [
        TOML.Token(:bare_key, "x"),
        TOML.Token(:whitespace, " "),
        TOML.Token(:equal, "="),
        TOML.Token(:whitespace, " "),
        TOML.Token(:float, "inf"),
    ]

    @test tokens("x = nan") == [
        TOML.Token(:bare_key, "x"),
        TOML.Token(:whitespace, " "),
        TOML.Token(:equal, "="),
        TOML.Token(:whitespace, " "),
        TOML.Token(:float, "nan"),
    ]

    @test tokens("""
    foo = true
    bar = false
    """) == [
        TOML.Token(:bare_key, "foo"),
        TOML.Token(:whitespace, " "),
        TOML.Token(:equal, "="),
        TOML.Token(:whitespace, " "),
        TOML.Token(:boolean, "true"),
        TOML.Token(:newline, "\n"),
        TOML.Token(:bare_key, "bar"),
        TOML.Token(:whitespace, " "),
        TOML.Token(:equal, "="),
        TOML.Token(:whitespace, " "),
        TOML.Token(:boolean, "false"),
        TOML.Token(:newline, "\n"),
    ]

    @test tokens("""
    foo = "text"
    """) == [
        TOML.Token(:bare_key, "foo"),
        TOML.Token(:whitespace, " "),
        TOML.Token(:equal, "="),
        TOML.Token(:whitespace, " "),
        TOML.Token(:basic_string, "\"text\""),
        TOML.Token(:newline, "\n"),
    ]

    @test tokens("""
    foo = \"\"\"
    "text1"
    ""text2""
    \"\"\"
    """) == [
        TOML.Token(:bare_key, "foo"),
        TOML.Token(:whitespace, " "),
        TOML.Token(:equal, "="),
        TOML.Token(:whitespace, " "),
        TOML.Token(:multiline_basic_string, "\"\"\"\n\"text1\"\n\"\"text2\"\"\n\"\"\""),
        TOML.Token(:newline, "\n"),
    ]

    @test tokens("""
    foo = 'text'
    """) == [
        TOML.Token(:bare_key, "foo"),
        TOML.Token(:whitespace, " "),
        TOML.Token(:equal, "="),
        TOML.Token(:whitespace, " "),
        TOML.Token(:literal_string, "'text'"),
        TOML.Token(:newline, "\n"),
    ]

    @test tokens("""
    foo = '''
    'text'
    ''text2''
    '''
    """) == [
        TOML.Token(:bare_key, "foo"),
        TOML.Token(:whitespace, " "),
        TOML.Token(:equal, "="),
        TOML.Token(:whitespace, " "),
        TOML.Token(:multiline_literal_string, "'''\n'text'\n''text2''\n'''"),
        TOML.Token(:newline, "\n"),
    ]

    @test tokens("x = []") == [
        TOML.Token(:bare_key, "x"),
        TOML.Token(:whitespace, " "),
        TOML.Token(:equal, "="),
        TOML.Token(:whitespace, " "),
        TOML.Token(:inline_array_begin, ""),
        TOML.Token(:single_bracket_left, "["),
        TOML.Token(:single_bracket_right, "]"),
        TOML.Token(:inline_array_end, ""),
    ]

    @test tokens("x = [1]") == [
        TOML.Token(:bare_key, "x"),
        TOML.Token(:whitespace, " "),
        TOML.Token(:equal, "="),
        TOML.Token(:whitespace, " "),
        TOML.Token(:inline_array_begin, ""),
        TOML.Token(:single_bracket_left, "["),
        TOML.Token(:decimal, "1"),
        TOML.Token(:single_bracket_right, "]"),
        TOML.Token(:inline_array_end, ""),
    ]

    @test tokens("x = [ 1 ]") == [
        TOML.Token(:bare_key, "x"),
        TOML.Token(:whitespace, " "),
        TOML.Token(:equal, "="),
        TOML.Token(:whitespace, " "),
        TOML.Token(:inline_array_begin, ""),
        TOML.Token(:single_bracket_left, "["),
        TOML.Token(:whitespace, " "),
        TOML.Token(:decimal, "1"),
        TOML.Token(:whitespace, " "),
        TOML.Token(:single_bracket_right, "]"),
        TOML.Token(:inline_array_end, ""),
    ]

    @test tokens("x = [1,]") == [
        TOML.Token(:bare_key, "x"),
        TOML.Token(:whitespace, " "),
        TOML.Token(:equal, "="),
        TOML.Token(:whitespace, " "),
        TOML.Token(:inline_array_begin, ""),
        TOML.Token(:single_bracket_left, "["),
        TOML.Token(:decimal, "1"),
        TOML.Token(:comma, ","),
        TOML.Token(:single_bracket_right, "]"),
        TOML.Token(:inline_array_end, ""),
    ]

    @test tokens("x = [ 1 , ]") == [
        TOML.Token(:bare_key, "x"),
        TOML.Token(:whitespace, " "),
        TOML.Token(:equal, "="),
        TOML.Token(:whitespace, " "),
        TOML.Token(:inline_array_begin, ""),
        TOML.Token(:single_bracket_left, "["),
        TOML.Token(:whitespace, " "),
        TOML.Token(:decimal, "1"),
        TOML.Token(:whitespace, " "),
        TOML.Token(:comma, ","),
        TOML.Token(:whitespace, " "),
        TOML.Token(:single_bracket_right, "]"),
        TOML.Token(:inline_array_end, ""),
    ]

    @test tokens("""
    x = [  
        1,  
        2, # comment
    ] # comment
    """) == [
        TOML.Token(:bare_key, "x"),
        TOML.Token(:whitespace, " "),
        TOML.Token(:equal, "="),
        TOML.Token(:whitespace, " "),
        TOML.Token(:inline_array_begin, ""),
        TOML.Token(:single_bracket_left, "["),
        TOML.Token(:whitespace, "  "),
        TOML.Token(:newline, "\n"),
        TOML.Token(:whitespace, "    "),
        TOML.Token(:decimal, "1"),
        TOML.Token(:comma, ","),
        TOML.Token(:whitespace, "  "),
        TOML.Token(:newline, "\n"),
        TOML.Token(:whitespace, "    "),
        TOML.Token(:decimal, "2"),
        TOML.Token(:comma, ","),
        TOML.Token(:whitespace, " "),
        TOML.Token(:comment, "# comment"),
        TOML.Token(:newline, "\n"),
        TOML.Token(:single_bracket_right, "]"),
        TOML.Token(:inline_array_end, ""),
        TOML.Token(:whitespace, " "),
        TOML.Token(:comment, "# comment"),
        TOML.Token(:newline, "\n"),
    ]

    @test tokens("x = [[]]") == [
        TOML.Token(:bare_key, "x"),
        TOML.Token(:whitespace, " "),
        TOML.Token(:equal, "="),
        TOML.Token(:whitespace, " "),
        TOML.Token(:inline_array_begin, ""),
        TOML.Token(:single_bracket_left, "["),
        TOML.Token(:inline_array_begin, ""),
        TOML.Token(:single_bracket_left, "["),
        TOML.Token(:single_bracket_right, "]"),
        TOML.Token(:inline_array_end, ""),
        TOML.Token(:single_bracket_right, "]"),
        TOML.Token(:inline_array_end, ""),
    ]

    @test tokens("""
    x = [[1,2],[3,4]]
    """) == [
        TOML.Token(:bare_key, "x"),
        TOML.Token(:whitespace, " "),
        TOML.Token(:equal, "="),
        TOML.Token(:whitespace, " "),
        TOML.Token(:inline_array_begin, ""),
        TOML.Token(:single_bracket_left, "["),
        TOML.Token(:inline_array_begin, ""),
        TOML.Token(:single_bracket_left, "["),
        TOML.Token(:decimal, "1"),
        TOML.Token(:comma, ","),
        TOML.Token(:decimal, "2"),
        TOML.Token(:single_bracket_right, "]"),
        TOML.Token(:inline_array_end, ""),
        TOML.Token(:comma, ","),
        TOML.Token(:inline_array_begin, ""),
        TOML.Token(:single_bracket_left, "["),
        TOML.Token(:decimal, "3"),
        TOML.Token(:comma, ","),
        TOML.Token(:decimal, "4"),
        TOML.Token(:single_bracket_right, "]"),
        TOML.Token(:inline_array_end, ""),
        TOML.Token(:single_bracket_right, "]"),
        TOML.Token(:inline_array_end, ""),
        TOML.Token(:newline, "\n"),
    ]

    @test tokens("""
    x = [
        [1,2,3],
        [4,5,6],
    ]
    """) == [
        TOML.Token(:bare_key, "x"),
        TOML.Token(:whitespace, " "),
        TOML.Token(:equal, "="),
        TOML.Token(:whitespace, " "),
        TOML.Token(:inline_array_begin, ""),
        TOML.Token(:single_bracket_left, "["),
        TOML.Token(:newline, "\n"),
        TOML.Token(:whitespace, "    "),
        TOML.Token(:inline_array_begin, ""),
        TOML.Token(:single_bracket_left, "["),
        TOML.Token(:decimal, "1"),
        TOML.Token(:comma, ","),
        TOML.Token(:decimal, "2"),
        TOML.Token(:comma, ","),
        TOML.Token(:decimal, "3"),
        TOML.Token(:single_bracket_right, "]"),
        TOML.Token(:inline_array_end, ""),
        TOML.Token(:comma, ","),
        TOML.Token(:newline, "\n"),
        TOML.Token(:whitespace, "    "),
        TOML.Token(:inline_array_begin, ""),
        TOML.Token(:single_bracket_left, "["),
        TOML.Token(:decimal, "4"),
        TOML.Token(:comma, ","),
        TOML.Token(:decimal, "5"),
        TOML.Token(:comma, ","),
        TOML.Token(:decimal, "6"),
        TOML.Token(:single_bracket_right, "]"),
        TOML.Token(:inline_array_end, ""),
        TOML.Token(:comma, ","),
        TOML.Token(:newline, "\n"),
        TOML.Token(:single_bracket_right, "]"),
        TOML.Token(:inline_array_end, ""),
        TOML.Token(:newline, "\n"),
    ]

    @test_throws TOML.ParseError("unexpected bare key 'y' at line 1") tokens("x = [1,2] y = 10")

    @test tokens("""
    x = {}
    """) == [
        TOML.Token(:bare_key, "x"),
        TOML.Token(:whitespace, " "),
        TOML.Token(:equal, "="),
        TOML.Token(:whitespace, " "),
        TOML.Token(:inline_table_begin, ""),
        TOML.Token(:curly_brace_left, "{"),
        TOML.Token(:curly_brace_right, "}"),
        TOML.Token(:inline_table_end, ""),
        TOML.Token(:newline, "\n"),
    ]


    @test tokens("""
    x = { y = 10 }
    """) == [
        TOML.Token(:bare_key, "x"),
        TOML.Token(:whitespace, " "),
        TOML.Token(:equal, "="),
        TOML.Token(:whitespace, " "),
        TOML.Token(:inline_table_begin, ""),
        TOML.Token(:curly_brace_left, "{"),
        TOML.Token(:whitespace, " "),
        TOML.Token(:bare_key, "y"),
        TOML.Token(:whitespace, " "),
        TOML.Token(:equal, "="),
        TOML.Token(:whitespace, " "),
        TOML.Token(:decimal, "10"),
        TOML.Token(:whitespace, " "),
        TOML.Token(:curly_brace_right, "}"),
        TOML.Token(:inline_table_end, ""),
        TOML.Token(:newline, "\n"),
    ]

    @test tokens("""
    x = { y = 10, z = 20 }
    """) == [
        TOML.Token(:bare_key, "x"),
        TOML.Token(:whitespace, " "),
        TOML.Token(:equal, "="),
        TOML.Token(:whitespace, " "),
        TOML.Token(:inline_table_begin, ""),
        TOML.Token(:curly_brace_left, "{"),
        TOML.Token(:whitespace, " "),
        TOML.Token(:bare_key, "y"),
        TOML.Token(:whitespace, " "),
        TOML.Token(:equal, "="),
        TOML.Token(:whitespace, " "),
        TOML.Token(:decimal, "10"),
        TOML.Token(:comma, ","),
        TOML.Token(:whitespace, " "),
        TOML.Token(:bare_key, "z"),
        TOML.Token(:whitespace, " "),
        TOML.Token(:equal, "="),
        TOML.Token(:whitespace, " "),
        TOML.Token(:decimal, "20"),
        TOML.Token(:whitespace, " "),
        TOML.Token(:curly_brace_right, "}"),
        TOML.Token(:inline_table_end, ""),
        TOML.Token(:newline, "\n"),
    ]

    @test_throws TOML.ParseError("unexpected '}' at line 1") tokens("x = { y }")
    @test_throws TOML.ParseError("unexpected bare key 'z' at line 1") tokens("x = { y = 10 z = 20 }")
    @test_throws TOML.ParseError("unexpected newline at line 1") tokens("x = { y = 10 \n}")

    @test tokens("""
    x = {y=[1,2]}
    """) == [
        TOML.Token(:bare_key, "x"),
        TOML.Token(:whitespace, " "),
        TOML.Token(:equal, "="),
        TOML.Token(:whitespace, " "),
        TOML.Token(:inline_table_begin, ""),
        TOML.Token(:curly_brace_left, "{"),
        TOML.Token(:bare_key, "y"),
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
        TOML.Token(:newline, "\n"),
    ]

    @test tokens("""
    x = {y=[1,2],z=[3,4]}
    """) == [
        TOML.Token(:bare_key, "x"),
        TOML.Token(:whitespace, " "),
        TOML.Token(:equal, "="),
        TOML.Token(:whitespace, " "),
        TOML.Token(:inline_table_begin, ""),
        TOML.Token(:curly_brace_left, "{"),
        TOML.Token(:bare_key, "y"),
        TOML.Token(:equal, "="),
        TOML.Token(:inline_array_begin, ""),
        TOML.Token(:single_bracket_left, "["),
        TOML.Token(:decimal, "1"),
        TOML.Token(:comma, ","),
        TOML.Token(:decimal, "2"),
        TOML.Token(:single_bracket_right, "]"),
        TOML.Token(:inline_array_end, ""),
        TOML.Token(:comma, ","),
        TOML.Token(:bare_key, "z"),
        TOML.Token(:equal, "="),
        TOML.Token(:inline_array_begin, ""),
        TOML.Token(:single_bracket_left, "["),
        TOML.Token(:decimal, "3"),
        TOML.Token(:comma, ","),
        TOML.Token(:decimal, "4"),
        TOML.Token(:single_bracket_right, "]"),
        TOML.Token(:inline_array_end, ""),
        TOML.Token(:curly_brace_right, "}"),
        TOML.Token(:inline_table_end, ""),
        TOML.Token(:newline, "\n"),
    ]

    @test tokens("x=[{foo=10}]") == [
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

    @test tokens("""
    x={foo={x=10}, bar={y=20},}
    """) == [
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
        TOML.Token(:newline, "\n"),
    ]

    @test tokens("""
    "foo"=100
    """) == [
        TOML.Token(:quoted_key, "\"foo\""),
        TOML.Token(:equal, "="),
        TOML.Token(:decimal, "100"),
        TOML.Token(:newline, "\n"),
    ]

    @test tokens("""
    [foo]
    """) == [
        TOML.Token(:table_begin, ""),
        TOML.Token(:single_bracket_left, "["),
        TOML.Token(:bare_key, "foo"),
        TOML.Token(:single_bracket_right, "]"),
        TOML.Token(:table_end, ""),
        TOML.Token(:newline, "\n"),
    ]

    @test tokens("""
    [foo.bar]
    """) == [
        TOML.Token(:table_begin, ""),
        TOML.Token(:single_bracket_left, "["),
        TOML.Token(:bare_key, "foo"),
        TOML.Token(:dot, "."),
        TOML.Token(:bare_key, "bar"),
        TOML.Token(:single_bracket_right, "]"),
        TOML.Token(:table_end, ""),
        TOML.Token(:newline, "\n"),
    ]

    @test tokens("""
    [foo.bar.baz]
    """) == [
        TOML.Token(:table_begin, ""),
        TOML.Token(:single_bracket_left, "["),
        TOML.Token(:bare_key, "foo"),
        TOML.Token(:dot, "."),
        TOML.Token(:bare_key, "bar"),
        TOML.Token(:dot, "."),
        TOML.Token(:bare_key, "baz"),
        TOML.Token(:single_bracket_right, "]"),
        TOML.Token(:table_end, ""),
        TOML.Token(:newline, "\n"),
    ]

    @test tokens("""
    ['foo']
    ["foo"]
    """) == [
        TOML.Token(:table_begin, ""),
        TOML.Token(:single_bracket_left, "["),
        TOML.Token(:quoted_key, "'foo'"),
        TOML.Token(:single_bracket_right, "]"),
        TOML.Token(:table_end, ""),
        TOML.Token(:newline, "\n"),
        TOML.Token(:table_begin, ""),
        TOML.Token(:single_bracket_left, "["),
        TOML.Token(:quoted_key, "\"foo\""),
        TOML.Token(:single_bracket_right, "]"),
        TOML.Token(:table_end, ""),
        TOML.Token(:newline, "\n"),
    ]

    @test tokens("""
    [foo."bar.baz"]
    """) == [
        TOML.Token(:table_begin, ""),
        TOML.Token(:single_bracket_left, "["),
        TOML.Token(:bare_key, "foo"),
        TOML.Token(:dot, "."),
        TOML.Token(:quoted_key, "\"bar.baz\""),
        TOML.Token(:single_bracket_right, "]"),
        TOML.Token(:table_end, ""),
        TOML.Token(:newline, "\n"),
    ]

    @test tokens("""
    [ foo . bar ]
    """) == [
        TOML.Token(:table_begin, ""),
        TOML.Token(:single_bracket_left, "["),
        TOML.Token(:whitespace, " "),
        TOML.Token(:bare_key, "foo"),
        TOML.Token(:whitespace, " "),
        TOML.Token(:dot, "."),
        TOML.Token(:whitespace, " "),
        TOML.Token(:bare_key, "bar"),
        TOML.Token(:whitespace, " "),
        TOML.Token(:single_bracket_right, "]"),
        TOML.Token(:table_end, ""),
        TOML.Token(:newline, "\n"),
    ]

    @test_throws TOML.ParseError("unexpected ']' at line 1") tokens("[]")
    @test_throws TOML.ParseError("unexpected ']' at line 1") tokens("[foo.]")
    @test_throws TOML.ParseError("unexpected newline at line 1") tokens("[\nfoo]")
    @test_throws TOML.ParseError("unexpected newline at line 1") tokens("[foo\n]")
    @test_throws TOML.ParseError("unexpected bare key 'bar' at line 1") tokens("[foo bar]")
    @test_throws TOML.ParseError("unexpected bare key 'x' at line 1") tokens("[foo] x = 10")

    @test tokens("""
    [[foo]]
    """) == [
        TOML.Token(:array_begin, ""),
        TOML.Token(:double_brackets_left, "[["),
        TOML.Token(:bare_key, "foo"),
        TOML.Token(:double_brackets_right, "]]"),
        TOML.Token(:array_end, ""),
        TOML.Token(:newline, "\n"),
    ]

    @test tokens("""
    [[foo.bar]]
    """) == [
        TOML.Token(:array_begin, ""),
        TOML.Token(:double_brackets_left, "[["),
        TOML.Token(:bare_key, "foo"),
        TOML.Token(:dot, "."),
        TOML.Token(:bare_key, "bar"),
        TOML.Token(:double_brackets_right, "]]"),
        TOML.Token(:array_end, ""),
        TOML.Token(:newline, "\n"),
    ]

    @test_throws TOML.ParseError("unexpected ']]' at line 1") tokens("[[]]")
    @test_throws TOML.ParseError("unexpected ']' at line 1") tokens("[[foo]")
    @test_throws TOML.ParseError("unexpected ']]' at line 1") tokens("[foo]]")
    @test_throws TOML.ParseError("unexpected bare key 'x' at line 1") tokens("[[foo]] x = 10")

    @test_throws TOML.ParseError("unexpected '!' at line 1") tokens("!")
    @test_throws TOML.ParseError("unexpected '!' at line 3") tokens("\n\n!")
    @test_throws TOML.ParseError("unexpected '\0' at line 1") tokens("# \0")
    @test_throws TOML.ParseError("unexpected end of file at line 1") tokens("x")
    @test_throws TOML.ParseError("unexpected end of file at line 1") tokens("x=")
    @test_throws TOML.ParseError("unexpected ',' at line 1") tokens("x,")
    @test_throws TOML.ParseError("unexpected 'p' at line 1") tokens("x = p")
    @test_throws TOML.ParseError("unexpected ',' at line 1") tokens("x = [,1]")
    @test_throws TOML.ParseError("unexpected ''' at line 1") tokens("x='foo")
    @test_throws TOML.ParseError("unexpected newline at line 1") tokens("x=\n10")
    @test_throws TOML.ParseError("unexpected bare key 'bar' at line 1") tokens("foo=100 bar=200")
    @test_throws TOML.ParseError("unexpected ']' at line 1") tokens("[]")
    @test_throws TOML.ParseError("unexpected ']' at line 1") tokens("[foo.]")
    @test_throws TOML.ParseError("unexpected '=' at line 1") tokens("[foo=]")
    @test_throws TOML.ParseError("unexpected ']]' at line 1") tokens("[foo]]")
    @test_throws TOML.ParseError("unexpected ']' at line 1") tokens("[[hoge]")
    @test_throws TOML.ParseError("unexpected ']]' at line 1") tokens("[[hoge.]]")
    @test_throws TOML.ParseError("unexpected end of file at line 1") tokens("[foo")
    @test_throws TOML.ParseError("unexpected ']' at line 1") tokens("x=[100]]")
    @test_throws TOML.ParseError("unexpected end of file at line 1") tokens("x=[100")
    @test_throws TOML.ParseError("unexpected '}' at line 1") tokens("x={foo}")
    @test_throws TOML.ParseError("unexpected ',' at line 1") tokens("x={,foo=100}")
    @test_throws TOML.ParseError("unexpected '.' at line 1") tokens("x={10.=10}")
    @test_throws TOML.ParseError("unexpected newline at line 1") tokens("x={\nfoo=100}")
    @test_throws TOML.ParseError("unexpected '\r' at line 1") tokens("foo=100\r")
    @test_throws TOML.ParseError("unexpected newline at line 11") tokens(
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
end

@testset "Parser" begin
    @test TOML.parse("") == Dict()
    @test TOML.parse("foo = 100") == Dict("foo" => 100)
    @test TOML.parse("foo = 100\nbar = 1.23") == Dict("foo" => 100, "bar" => 1.23)
    @test TOML.parse("sushi = \"🍣\"\nbeer = \"🍺\"") == Dict("sushi" => "🍣", "beer" => "🍺")
    @test TOML.parse("name = { first = \"Tom\", last = \"Preston-Werner\" }") == Dict("name" => Dict("first" => "Tom", "last" => "Preston-Werner"))
    @test TOML.parse("x = {foo = 10, bar = { a = 1, b = 2 }, baz = {}}") == Dict("x" => Dict("foo" => 10, "bar" => Dict("a" => 1, "b" => 2), "baz" => Dict()))


    data = TOML.parse("x = [1]\ny = [1,2,3]\nz = []")
    @test data == Dict("x" => [1], "y" => [1,2,3], "z" => [])
    @test data["x"] isa Vector{Int}
    @test data["y"] isa Vector{Int}
    @test data["z"] isa Vector{Any}

    data = TOML.parse("x = [[1,2,3], [1,2]]\ny = [[1,2]]\nz = [[[]]]")
    @test data == Dict("x" => [[1,2,3], [1,2]], "y" => [[1,2]], "z" => [[[]]])
    @test data["x"] isa Vector{Vector}

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
end
