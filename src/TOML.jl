module TOML

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

function ensurebytes!(input::IO, buffer::Buffer, n::Int)
    if buffer.p_end - buffer.p + 1 ≥ n
        # ok
        return true
    end
    fillbuffer!(input, buffer)
    return buffer.p_end - buffer.p + 1 ≥ n
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

include("value.jl")

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
isinteger(token::Token) = token.kind == :integer || token.kind == :binary || token.kind == :octal || token.kind == :hexadecimal
isfloat(token::Token) = token.kind == :float
isboolean(token::Token) = token.kind == :boolean
isdatetime(token::Token) = token.kind == :datetime
isatomicvalue(token::Token) = isstring(token) || isinteger(token) || isfloat(token) || isboolean(token) || isdatetime(token)
iscontainer(token::Token) = token.kind ∈ (:single_bracket_left, :curly_brace_left)
iskey(token::Token) = token.kind == :bare_key || token.kind == :quoted_key
iseof(token::Token) = token.kind == :eof

# Human-readable description of token.
function tokendesc(token::Token)
    if isstring(token)
        return "string"
    elseif token.kind == :integer
        return "integer"
    elseif token.kind == :float
        return "floating-point number"
    elseif token.kind == :boolean
        return "boolean"
    elseif token.kind == :datetime
        return "datetime"
    elseif token.kind == :bare_key
        return "bare key '$(token.text)'"
    elseif token.kind == :quoted_key
        return "quoted key"
    elseif token.kind == :eof
        return "end of file"
    elseif token.kind == :comma
        return "','"
    elseif token.kind == :dot
        return "'.'"
    elseif token.kind == :equal
        return "'='"
    elseif token.kind == :single_bracket_left
        return "'['"
    elseif token.kind == :single_bracket_right
        return "']'"
    elseif token.kind == :double_brackets_left
        return "'[['"
    elseif token.kind == :double_brackets_right
        return "']]'"
    elseif token.kind == :curly_brace_left
        return "'{'"
    elseif token.kind == :curly_brace_right
        return "'}'"
    else
        return string(token.kind)
    end
end

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

iswhitespace(char::Char) = char == ' ' || char == '\t'
iskeychar(char::Char) = 'A' ≤ char ≤ 'Z' || 'a' ≤ char ≤ 'z' || '0' ≤ char ≤ '9' || char == '-' || char == '_'

struct ParseError <: Exception
    msg::String
end

parse_error(msg, linenum) = throw(ParseError("$(msg) at line $(linenum)"))
unexpectedtoken(token, linenum) = parse_error("unexpected $(tokendesc(token))", token.kind == :newline ? linenum - 1 : linenum)

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
                    parse_error("line feed (LF) is expected after carriage return (CR)", reader.linenum)
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
            kind, n = scanvalue(input, buffer)
            if kind == :novalue
                parse_error("invalid value format", reader.linenum)
            elseif kind == :eof
                parse_error("unexpected end of file", reader.linenum)
            end
            reader.expectvalue = false
            return Token(kind, taketext!(buffer, n))
        elseif char == '='
            consume!(buffer, 1)
            reader.expectvalue = true
            return Token(:equal, "=")
        elseif iskeychar(char)  # bare key
            n = scanwhile(iskeychar, input, buffer)
            return Token(:bare_key, taketext!(buffer, n))
        elseif char == '"' || char == '\''  # quoted key
            n = scanpattern(char == '"' ? RE_BASIC_STRING : RE_LITERAL_STRING, input, buffer)
            if n < 2  # the minimum quoted key is "" or ''
                parse_error("invalid quoted key", reader.linenum)
            end
            return Token(:quoted_key, taketext!(buffer, n))
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
                parse_error("unexpected ','", reader.linenum)
            end
        elseif char == '}'  # inline table
            consume!(buffer, 1)
            return Token(:curly_brace_right, "}")
        else
            parse_error("unexpected '$(char)'", reader.linenum)
        end
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
    stack = reader.stack
    top = isempty(stack) ? :none : stack[end]
    token = peektoken(reader)
    if top == :inline_array
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
        elseif token.kind == :curly_brace_left
            readtoken(reader)
            accept(token)
            push!(stack, :inline_table)
            return TOKEN_INLINE_TABLE_BEGIN
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
            unexpectedtoken(token, reader.linenum)
        end
    elseif top == :inline_table
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
            elseif isatomicvalue(peektoken(reader)) || iscontainer(peektoken(reader))
                # ok
            elseif peektoken(reader).kind ∈ (:curly_brace_right, :bare_key, :quoted_key, :whitespace)
                # ok
            else
                unexpectedtoken(peektoken(reader), reader.linenum)
            end
            return token
        else
            unexpectedtoken(token, reader.linenum)
        end
    elseif token.kind ∈ (:eof, :comment, :whitespace, :newline)
        readtoken(reader)
        return token
    elseif token.kind ∈ (:bare_key, :quoted_key)
        value = parsekeyvalue(reader)
        if isatomicvalue(value) && peektoken(reader).kind == :whitespace
            accept(readtoken(reader))
            if peektoken(reader).kind ∉ (:newline, :comment)
                unexpectedtoken(peektoken(reader), reader.linenum)
            end
        end
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
                unexpectedtoken(token, reader.linenum)
            end
            while (token = readtoken(reader)).kind != close
                if token.kind == :dot
                    accept(token)
                else
                    unexpectedtoken(token, reader.linenum)
                end
                token = readtoken(reader)
                token.kind == :whitespace && (accept(token); token = readtoken(reader))
                if token.kind ∈ (:bare_key, :quoted_key)
                    accept(token)
                    peektoken(reader).kind == :whitespace && accept(readtoken(reader))
                else
                    unexpectedtoken(token, reader.linenum)
                end
            end
            if token.kind != close
                unexpectedtoken(token, reader.linenum)
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
        unexpectedtoken(token, reader.linenum)
    end
end

function parsekeyvalue(reader::StreamReader)
    # (bare_key | quoted_key) whitespace? '=' whitespace? (atomic_value | '[' | '{')
    accept(token) = push!(reader.parsequeue, token)
    emitkey = false
    @label readkey
    token = readtoken(reader)
    if !iskey(token)
        unexpectedtoken(token, reader.linenum)
    elseif emitkey
        accept(token)
    end
    token = readtoken(reader)
    if token.kind == :whitespace
        accept(token)
        token = readtoken(reader)
    end
    if token.kind == :equal
        accept(token)
    elseif token.kind == :dot
        # dotted keys
        accept(token)
        if peektoken(reader).kind == :whitespace
            accept(readtoken(reader))
        end
        emitkey = true
        @goto readkey
    else
        unexpectedtoken(token, reader.linenum)
    end
    token = readtoken(reader)
    if token.kind == :whitespace
        accept(token)
        token = readtoken(reader)
    end
    if isatomicvalue(token)
        accept(token)
        return token
    elseif token.kind == :single_bracket_left  # inline array
        accept(TOKEN_INLINE_ARRAY_BEGIN)
        accept(token)
        push!(reader.stack, :inline_array)
        return token
    elseif token.kind == :curly_brace_left  # inline table
        accept(TOKEN_INLINE_TABLE_BEGIN)
        accept(token)
        push!(reader.stack, :inline_table)
        return token
    else
        unexpectedtoken(token, reader.linenum)
    end
end

function debug(str::AbstractString)
    tokens = Token[]
    reader = StreamReader(IOBuffer(str))
    lasttoken = nothing
    while true
        try
            token = parsetoken(reader)
            if token.kind == :eof
                break
            else
                push!(tokens, token)
            end
            lasttoken = token
        catch
            @show lasttoken
            rethrow()
        end
    end
    return tokens
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
