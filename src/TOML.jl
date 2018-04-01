module TOML

import Automa
import Automa.RegExp: @re_str, primitive

const rep = Automa.RegExp.rep
const opt = Automa.RegExp.opt
const ++ = *

# Values are a piece of text that may occur:
# 1. after the '=' mark, or
# 2. in an array.
const value_machine = (function()
    string = let
        utf8 = (
            # 1-byte
            (primitive(0x00:0x7f)) |
            # 2-byte
            (primitive(0xc0:0xdf) ++ primitive(0x80:0xbf)) |
            # 3-byte
            (primitive(0xe0:0xef) ++ primitive(0x80:0xbf) ++ primitive(0x80:0xbf)) |
            # 4-byte
            (primitive(0xf0:0xf7) ++ primitive(0x80:0xbf) ++ primitive(0x80:0xbf) ++ primitive(0x80:0xbf))
        )
        #utf8 = primitive(0x00:0xff)
        control = primitive(0x00:0x1f)
        escape = re"\\" ++ (re"[btnfr]" | re"\"" | re"\\")
        hex(n) = ++([re"[0-9A-Fa-f]" for _ in 1:n]...)
        unicode = re"\\" ++ ((re"u" ++ hex(4)) | (re"U" ++ hex(8)))

        # basic string
        basic = primitive('"') ++ rep((utf8 \ (control | re"\"" | re"\\")) | escape | unicode) ++ primitive('"')
        basic.actions[:exit] = [:basic_string]

        tripledquote = primitive("\"\"\"")
        newline = re"\r?\n"

        # multi-line basic string
        multiline_basic = tripledquote ++ rep((utf8 \ control) | (opt('"') ++ newline) | escape | unicode) ++ tripledquote
        multiline_basic.actions[:exit] = [:multiline_basic_string]

        # literal string
        literal = primitive('\'') ++ rep(utf8 \ control) ++ primitive('\'')
        literal.actions[:exit] = [:literal_string]

        # multi-line literal string
        triplesquote = primitive("'''")
        multiline_literal = triplesquote ++ rep((utf8 \ control) | newline) ++ triplesquote
        multiline_literal.actions[:exit] = [:multiline_literal_string]

        basic | multiline_basic | literal | multiline_literal
    end

    integer = re"[-+]?" ++ re"0|[1-9](_?[0-9])*"
    integer.actions[:exit] = [:integer]

    float = let
        int = re"[-+]?" ++ re"0|[1-9](_?[0-9])*"
        fractional = int ++ re"\.(_?[0-9])*"
        exponent = re"[eE]" ++ int
        fractional ++ opt(exponent)
    end
    float.actions[:exit] = [:float]

    boolean = re"true|false"
    boolean.actions[:exit] = [:boolean]

    datetime = let
        twodigits = re"[0-9][0-9]"
        fourdigits = re"[0-9][0-9][0-9][0-9]"

        time_secfrac = re"\.[0-9]+"
        time_numoffset = re"[-+]" ++ twodigits ++ re":" ++ twodigits
        time_offset = re"Z" | time_numoffset

        partial_time = twodigits ++ re":" ++ twodigits ++ re":" ++ twodigits ++ opt(time_secfrac)
        full_date = fourdigits ++ re"-" ++ twodigits ++ re"-" ++ twodigits
        full_time = partial_time ++ time_offset

        full_date ++ re"T" ++ full_time
    end
    datetime.actions[:exit] = [:datetime]

    value = string | integer | float | boolean | datetime

    lookahead = re"[ \r\n\t,\]}#]?"
    lookahead.actions[:enter] = [:escape]

    Automa.compile(value ++ lookahead)
end)()

#write("value.dot", Automa.machine2dot(value_machine))
#run(`dot -Tsvg -o value.svg value.dot`)

const actions = Dict(
    :basic_string => :(kind = :basic_string),
    :multiline_basic_string => :(kind = :multiline_basic_string),
    :literal_string => :(kind = :literal_string),
    :multiline_literal_string => :(kind = :multiline_literal_string),
    :integer => :(kind = :integer),
    :float => :(kind = :float),
    :boolean => :(kind = :boolean),
    :datetime => :(kind = :datetime),
    :escape => :(@escape),
)

context = Automa.CodeGenContext(generator=:table)
@eval function scan(data)
    kind = :none
    $(Automa.generate_init_code(context, value_machine))
    p_end = p_eof = sizeof(data)
    $(Automa.generate_exec_code(context, value_machine, actions))
    return kind
end

mutable struct Buffer
    data::Vector{UInt8}
    p::Int
    p_end::Int
    p_eof::Int

    function Buffer()
        data = Vector{UInt8}(undef, 16)
        return new(data, 1, 0, -1)
    end
end

function fillbuffer!(input::IO, buffer::Buffer)
    if buffer.p_eof ≥ 0
        return 0
    end
    #p = buffer.p + offset
    if (len = buffer.p_end - buffer.p + 1) > 0
        copyto!(buffer.data, 1, buffer.data, buffer.p, len)
        buffer.p_end -= buffer.p - 1
        buffer.p = 1
        if buffer.p_eof != -1
            buffer.p_eof -= len
        end
    end
    n::Int = length(buffer.data) - buffer.p_end
    if n == 0
        resize!(buffer.data, length(buffer.data) * 2)
        n = length(buffer.data) - buffer.p_end
    end
    if eof(input)
        buffer.p_eof = buffer.p_end
        return 0
    else
        n = min(n, bytesavailable(input))
        unsafe_read(input, pointer(buffer.data, buffer.p_end + 1), n)
        buffer.p_end += n
        return n
    end
end

function peekchar(input::IO, buffer::Buffer; offset::Int=0)
    # TODO: support unicode
    if buffer.p + offset > buffer.p_end
        fillbuffer!(input, buffer)
    end
    p = buffer.p + offset
    if p ≤ buffer.p_end
        b = buffer.data[p]
        @assert 0x00 ≤ b ≤ 0x7f
        return Char(b), 1
    else
        return nothing
    end
end

function scanwhile(f::Function, input::IO, buffer::Buffer; offset::Int=0)
    o = offset
    while (char_n = peekchar(input, buffer, offset=o)) != nothing
        char, n = char_n
        if !f(char)
            break
        end
        o += n
    end
    return o - offset
end

function taketext!(buffer::Buffer, size::Int)
    text = String(buffer.data[buffer.p:buffer.p+size-1])
    buffer.p += size
    return text
end

function consume!(buffer::Buffer, size::Int)
    buffer.p += size
    return
end

struct Token
    kind::Symbol
    text::String
end

Base.:(==)(t1::Token, t2::Token) = t1.kind == t2.kind && t1.text == t2.text

const TOKEN_ARRAY_BEGIN = Token(:array_begin, "")
const TOKEN_ARRAY_END   = Token(:array_end,   "")
const TOKEN_TABLE_BEGIN = Token(:table_begin, "")
const TOKEN_TABLE_END   = Token(:table_end,   "")

const TOKEN_INLINE_ARRAY_BEGIN = Token(:inline_array_begin, "")
const TOKEN_INLINE_ARRAY_END   = Token(:inline_array_end,   "")
const TOKEN_INLINE_TABLE_BEGIN = Token(:inline_table_begin, "")
const TOKEN_INLINE_TABLE_END   = Token(:inline_table_end,   "")

const TOKEN_INIT = Token(:init, "")
const TOKEN_EOF = Token(:eof, "")

istext(token::Token) = !isempty(token.text)
isevent(token::Token) = !istext(token)
isstring(token::Token) = token.kind ∈ (:basic_string, :multiline_basic_string, :literal_string, :multiline_literal_string)
isinteger(token::Token) = token.kind == :integer
isfloat(token::Token) = token.kind == :float
isboolean(token::Token) = token.kind == :boolean
isdatetime(token::Token) = token.kind == :datetime
isatomicvalue(token::Token) = isstring(token) || isinteger(token) || isfloat(token) || isboolean(token) || isdatetime(token)
iskey(token::Token) = token.kind == :bare_key || token.kind == :quoted_key
iseof(token::Token) = token.kind == :eof

function keyname(token::Token)
    if token.kind == :bare_key
        return token.text
    elseif token.kind == :quoted_key
        # FIXME
        return token.text[2:end-1]
    else
        throw(ArgumentError("not a key token"))
    end
end

function value(token::Token)
    if token.kind == :integer
        return Base.parse(Int, token.text)
    elseif token.kind == :float
        return Base.parse(Float64, token.text)
    elseif token.kind == :boolean
        return token.text[1] == 't' ? true : false
    elseif token.kind == :literal_string
        return token.text[2:end-1]
    elseif token.kind == :multiline_literal_string
        return token.text[4:end-3]
    # FIXME: datetime, strings,
    else
        throw(ArgumentError("not a value token"))
    end
end


mutable struct StreamReader
    input::IO
    buffer::Buffer

    # mutable state
    linenum::Int
    expectvalue::Bool
    stack::Vector{Symbol}
    queue::Vector{Token}
    parsequeue::Vector{Token}
end

function StreamReader(input::IO)
    return StreamReader(input, Buffer(), 1, false, Symbol[], Token[], Token[])
end

context = Automa.CodeGenContext(generator=:goto)
@eval function scanvalue(data::Vector{UInt8}, p::Int, p_end::Int, p_eof::Int, cs::Int)
    kind = :incomplete
    $(Automa.generate_exec_code(context, value_machine, actions))
    if cs ≥ 0 && kind != :incomplete && !(0 ≤ p_eof < p)
        p -= 1  # cancel look-ahead
    end
    return kind, p, cs
end

iswhitespace(char::Char) = char == ' ' || char == '\t'
iskeychar(char::Char) = 'A' ≤ char ≤ 'Z' || 'a' ≤ char ≤ 'z' || '0' ≤ char ≤ '9' || char == '-' || char == '_'

struct ParserError <: Exception
    msg::String
end

throw_parse_error(msg) = throw(ParserError(msg))

function readtoken(reader::StreamReader)
    if !isempty(reader.queue)
        return popfirst!(reader.queue)
    end
    input = reader.input
    buffer = reader.buffer
    stack = reader.stack
    queue = reader.queue
    while (char_n = peekchar(input, buffer)) != nothing
        char, n = char_n
        if iswhitespace(char)  # space or tab
            n = scanwhile(iswhitespace, input, buffer)
            return Token(:whitespace, taketext!(buffer, n))
        elseif char ∈ ('\r', '\n')  # newline
            consume!(buffer, 1)
            if char == '\r'
                if peekchar(input, buffer) == ('\n', 1)
                    consume!(buffer, 1)
                    reader.linenum += 1
                    return Token(:newline, "\r\n")
                else
                    throw_parse_error("line feed character is expected at line $(reader.linenum)")
                end
            else
                reader.linenum += 1
                return Token(:newline, "\n")
            end
        elseif reader.expectvalue
            if char == '['
                consume!(buffer, 1)
                return Token(:single_bracket_left, "[")
            elseif char == ']'
                consume!(buffer, 1)
                return Token(:single_bracket_right, "]")
            elseif char == '{'
                consume!(buffer, 1)
                reader.expectvalue = false
                return Token(:curly_brace_left, "{")
            end
            kind = :undef
            p = buffer.p
            cs = 1
            while true
                kind, p, cs = scanvalue(buffer.data, p, buffer.p_end, buffer.p_eof, cs)
                if cs < 0
                    throw_parse_error("unexpected value format at line $(reader.linenum)")
                elseif kind == :incomplete
                    fillbuffer!(input, buffer)
                    p = buffer.p
                    cs = 1
                else
                    break
                end
            end
            reader.expectvalue = false
            return Token(kind, taketext!(buffer, p - buffer.p))
        elseif char == '='
            consume!(buffer, 1)
            reader.expectvalue = true
            return Token(:equal, "=")
        elseif iskeychar(char)  # bare key
            n = scanwhile(iskeychar, input, buffer)
            return Token(:bare_key, taketext!(buffer, n))
        elseif char == '"'  # quoted key
            # FIXME: this is not perfect
            n = scanwhile(c -> c != '"', input, buffer; offset=1)
            return Token(:quoted_key, taketext!(buffer, n+2))
        elseif char == '#'  # comment
            n = scanwhile(c -> c != '\r' && c != '\n', input, buffer)
            return Token(:comment, taketext!(buffer, n))
        elseif char == '['  # table or array of tables
            consume!(buffer, 1)
            if peekchar(input, buffer) == ('[', 1)
                consume!(buffer, 1)
                return Token(:double_brackets_left, "[[")
            else
                return Token(:single_bracket_left, "[")
            end
        elseif char == ']'  # table, array of tables, or inline table
            consume!(buffer, 1)
            if !isempty(reader.stack) && reader.stack[end] == :inline_array
                return Token(:single_bracket_right, "]")
            elseif peekchar(input, buffer) == (']', 1)
                consume!(buffer, 1)
                return Token(:double_brackets_right, "]]")
            else
                return Token(:single_bracket_right, "]")
            end
        elseif char == '.'  # dot
            consume!(buffer, 1)
            return Token(:dot, ".")
        elseif char == ','  # comma
            consume!(buffer, 1)
            if !isempty(reader.stack) && reader.stack[end] == :inline_array
                reader.expectvalue = true
                return Token(:comma, ",")
            elseif !isempty(reader.stack) && reader.stack[end] == :inline_table
                reader.expectvalue = false
                return Token(:comma, ",")
            else
                throw_parse_error("unexpected ',' at line $(reader.linenum)")
            end
        elseif char == '}'  # inline table
            consume!(buffer, 1)
            return Token(:curly_brace_right, "}")
        else
            throw(ParserError("unexpected character '$(char)' at line $(reader.linenum)"))
        end
    end
    if !isempty(reader.stack)
        throw_parse_error("unexpected end of file")
    end
    return TOKEN_EOF
end

function peektoken(reader::StreamReader)
    if !isempty(reader.queue)
        return reader.queue[1]
    end
    token = readtoken(reader)
    push!(reader.queue, token)
    return token
end

function parsetoken(reader::StreamReader)
    #@show reader.stack peektoken(reader)
    if !isempty(reader.parsequeue)
        return popfirst!(reader.parsequeue)
    end
    accept(token) = push!(reader.parsequeue, token)
    top() = isempty(reader.stack) ? :none : reader.stack[end]
    stack = reader.stack
    token = peektoken(reader)
    if top() == :inline_array
        if token.kind ∈ (:comment, :whitespace, :newline)
            readtoken(reader)
            return token
        elseif token.kind == :single_bracket_left
            readtoken(reader)
            accept(token)
            push!(stack, :inline_array)
            return TOKEN_INLINE_ARRAY_BEGIN
        elseif token.kind == :single_bracket_right
            readtoken(reader)
            pop!(stack)
            accept(TOKEN_INLINE_ARRAY_END)
            while peektoken(reader).kind ∈ (:comment, :whitespace, :newline)
                accept(readtoken(reader))
            end
            if peektoken(reader).kind == :comma
                accept(readtoken(reader))
            end
            return token
        elseif isatomicvalue(token)
            readtoken(reader)
            while peektoken(reader).kind ∈ (:comment, :whitespace, :newline)
                accept(readtoken(reader))
            end
            if peektoken(reader).kind == :comma
                accept(readtoken(reader))
            end
            return token
        else
            throw_parse_error("unexpected token at line $(reader.linenum)")
        end
    elseif top() == :inline_table
        if token.kind == :whitespace
            readtoken(reader)
            return token
        elseif token.kind == :curly_brace_right
            readtoken(reader)
            pop!(stack)
            accept(TOKEN_INLINE_TABLE_END)
            return token
        elseif token.kind ∈ (:bare_key, :quoted_key)
            parsekeyvalue(reader)
            if peektoken(reader).kind == :whitespace
                accept(readtoken(reader))
            end
            if peektoken(reader).kind == :comma
                accept(readtoken(reader))
            elseif peektoken(reader).kind ∈ (:curly_brace_right, :bare_key, :quoted_key, :whitespace)
                # ok
            else
                throw_parse_error("unexpected token")
            end
            return token
        else
            throw_parse_error("unexpected token at line $(reader.linenum)")
        end
    elseif token.kind ∈ (:eof, :comment, :whitespace, :newline)
        readtoken(reader)
        return token
    elseif token.kind ∈ (:bare_key, :quoted_key)
        parsekeyvalue(reader)
        return token
    elseif token.kind ∈ (:single_bracket_left, :double_brackets_left)
        # '['  whitespace? ((bare_key|quoted_key) whitespace?) ('.' whitespace? (bare_key|quoted_key) whitespace?)*  ']'
        # '[[' whitespace? ((bare_key|quoted_key) whitespace?) ('.' whitespace? (bare_key|quoted_key) whitespace?)* ']]'
        close = token.kind == :single_bracket_left ? :single_bracket_right : :double_brackets_right
        readtoken(reader)
        accept(token)
        let token = readtoken(reader)
            token.kind == :whitespace && (accept(token); token = readtoken(reader))
            if token.kind ∈ (:bare_key, :quoted_key)
                accept(token)
                peektoken(reader).kind == :whitespace && accept(readtoken(reader))
            else
                throw_parse_error("unexpected token at line $(reader.linenum)")
            end
            while (token = readtoken(reader)).kind != close
                if token.kind == :dot
                    accept(token)
                else
                    throw_parse_error("unexpected token at line $(reader.linenum)")
                end
                token = readtoken(reader)
                token.kind == :whitespace && (accept(token); token = readtoken(reader))
                if token.kind ∈ (:bare_key, :quoted_key)
                    accept(token)
                    peektoken(reader).kind == :whitespace && accept(readtoken(reader))
                end
            end
            if token.kind != close
                throw_parse_error("unexpected token at line $(reader.linenum)")
            end
            accept(token)
        end
        if token.kind == :single_bracket_left
            accept(TOKEN_TABLE_END)
            return TOKEN_TABLE_BEGIN
        else
            accept(TOKEN_ARRAY_END)
            return TOKEN_ARRAY_BEGIN
        end
    else
        throw_parse_error("unexpected token at line $(reader.linenum)")
    end
end

function parsekeyvalue(reader::StreamReader)
    # (bare_key | quoted_key) whitespace? '=' whitespace? (atomic_value | '[' | '{')
    accept(token) = push!(reader.parsequeue, token)
    token = readtoken(reader)
    @assert token.kind ∈ (:bare_key, :quoted_key)
    token = readtoken(reader)
    if token.kind == :whitespace
        accept(token)
        token = readtoken(reader)
    end
    if token.kind == :equal
        accept(token)
    else
        throw_parse_error("unexpected token")
    end
    token = readtoken(reader)
    if token.kind == :whitespace
        accept(token)
        token = readtoken(reader)
    end
    if isatomicvalue(token)
        accept(token)
    elseif token.kind == :single_bracket_left  # inline array
        accept(TOKEN_INLINE_ARRAY_BEGIN)
        accept(token)
        push!(reader.stack, :inline_array)
    elseif token.kind == :curly_brace_left  # inline table
        accept(TOKEN_INLINE_TABLE_BEGIN)
        accept(token)
        push!(reader.stack, :inline_table)
    else
        throw_parse_error("unexpected token")
    end
    return nothing
end

function parse(str::AbstractString)
    reader = StreamReader(IOBuffer(str))
    root = Dict{String,Any}()
    current = root
    while (token = parsetoken(reader)).kind != :eof
        if iskey(token)
            key = keyname(token)
            token = nextvalue(reader)
            if isatomicvalue(token)
                current[key] = value(token)
            elseif token.kind == :inline_array_begin
                current[key] = parsearray(reader)
            elseif token.kind == :inline_table_begin
                current[key] = parsetable(reader)
            end
        elseif token.kind == :table_begin
            current = root
            while (token = parsetoken(reader)).kind != :table_end
                if iskey(token)
                    current = get!(current, keyname(token), Dict{String,Any}())
                end
            end
        #elseif token.kind == :array_begin
        else
            # ignore
        end
    end
    return root
end

function nextkey(reader)
    while true
        token = parsetoken(reader)
        if iskey(token) || token.kind == :inline_table_end
            return token
        elseif token.kind == :eof
            throw(ArgumentError("found no key"))
        end
    end
end

function nextvalue(reader)
    while true
        token = parsetoken(reader)
        if isatomicvalue(token) || token.kind ∈ (:inline_array_begin, :inline_array_end, :inline_table_begin, :inline_table_end)
            return token
        elseif token.kind == :eof
            throw(ArgumentError("found no value"))
        end
    end
end

function parsearray(reader)
    array = []
    while true
        token = nextvalue(reader)
        if isatomicvalue(token)
            if isempty(array)
                array = [value(token)]
            else
                push!(array, value(token))
            end
        elseif token.kind == :inline_array_begin
            push!(array, parsearray(reader))
        elseif token.kind == :inline_table_begin
            push!(array, parsetable(reader))
        else
            @assert token.kind == :inline_array_end
            break
        end
    end
    return array
end

function parsetable(reader)
    table = Dict{String,Any}()
    while true
        token = nextkey(reader)
        if token.kind == :inline_table_end
            break
        end
        key = keyname(token)
        token = nextvalue(reader)
        if isatomicvalue(token)
            table[key] = value(token)
        elseif token.kind == :inline_array_begin
            table[key] = parsearray(reader)
        elseif token.kind == :inline_table_begin
            table[key] = parsetable(reader)
        else
            @assert token.kind == :inline_table_end
            break
        end
    end
    return table
end

end # module
