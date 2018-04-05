# Parser
# ======

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
    while (char_n = peekchar(input, buffer))[2] > 0
        char, n = char_n
        if iswhitespace(char)  # space or tab
            n = scanwhitespace(input, buffer)
            if n == 1
                consume!(buffer, 1)
                if char == ' '
                    return TOKEN_WHITESPACE_SPACE
                else
                    return TOKEN_WHITESPACE_TAB
                end
            else
                return Token(:whitespace, taketext!(buffer, n))
            end
        elseif char ∈ ('\r', '\n')  # newline
            consume!(buffer, 1)
            if char == '\r'
                if peekchar(input, buffer) == ('\n', 1)
                    consume!(buffer, 1)
                    reader.linenum += 1
                    return TOKEN_NEWLINE_CRLF
                else
                    parse_error("line feed (LF) is expected after carriage return (CR)", reader.linenum)
                end
            else
                reader.linenum += 1
                return TOKEN_NEWLINE_LF
            end
        elseif char == '#'  # comment
            n = scanwhile(c -> c != '\r' && c != '\n', input, buffer)
            return Token(:comment, taketext!(buffer, n))
        elseif reader.expectvalue
            if char == '['
                consume!(buffer, 1)
                return TOKEN_SINGLE_BRACKET_LEFT
            elseif char == ']'
                consume!(buffer, 1)
                return TOKEN_SINGLE_BRACKET_RIGHT
            elseif char == '{'
                consume!(buffer, 1)
                reader.expectvalue = false
                return TOKEN_CURLY_BRACE_LEFT
            end
            kind, n = scanvalue(input, buffer)
            if kind == :novalue
                parse_error("invalid value format", reader.linenum)
            elseif kind == :eof
                parse_error("unexpected end of file", reader.linenum)
            end
            reader.expectvalue = false
            token = Token(kind, taketext!(buffer, n))
            if token.kind ∈ (:multiline_basic_string, :multiline_literal_string)
                # multiline strings may contain newlines
                reader.linenum += countlines(token)
            end
            return token
        elseif char == '='
            consume!(buffer, 1)
            reader.expectvalue = true
            return TOKEN_EQUAL
        elseif iskeychar(char)  # bare key
            n = scanbarekey(input, buffer)
            return Token(:bare_key, taketext!(buffer, n))
        elseif char == '"' || char == '\''  # quoted key
            n = scanpattern(char == '"' ? RE_BASIC_STRING : RE_LITERAL_STRING, input, buffer)
            if n < 2  # the minimum quoted key is "" or ''
                parse_error("invalid quoted key", reader.linenum)
            end
            return Token(:quoted_key, taketext!(buffer, n))
        elseif char == '['  # table or array of tables
            consume!(buffer, 1)
            if peekchar(input, buffer) == ('[', 1)
                consume!(buffer, 1)
                return TOKEN_DOUBLE_BRACKETS_LEFT
            else
                return TOKEN_SINGLE_BRACKET_LEFT
            end
        elseif char == ']'  # table, array of tables, or inline table
            consume!(buffer, 1)
            if !isempty(reader.stack) && reader.stack[end] == :inline_array
                return TOKEN_SINGLE_BRACKET_RIGHT
            elseif peekchar(input, buffer) == (']', 1)
                consume!(buffer, 1)
                return TOKEN_DOUBLE_BRACKETS_RIGHT
            else
                return TOKEN_SINGLE_BRACKET_RIGHT
            end
        elseif char == '.'  # dot
            consume!(buffer, 1)
            return TOKEN_DOT
        elseif char == ','  # comma
            consume!(buffer, 1)
            if !isempty(reader.stack) && reader.stack[end] == :inline_array
                reader.expectvalue = true
                return TOKEN_COMMA
            elseif !isempty(reader.stack) && reader.stack[end] == :inline_table
                reader.expectvalue = false
                return TOKEN_COMMA
            else
                parse_error("unexpected ','", reader.linenum)
            end
        elseif char == '}'  # inline table
            consume!(buffer, 1)
            return TOKEN_CURLY_BRACE_RIGHT
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
    emit(token) = push!(reader.parsequeue, token)
    stack = reader.stack
    top = isempty(stack) ? :none : stack[end]
    token = peektoken(reader)
    if top == :inline_array
        if token.kind ∈ (:comment, :whitespace, :newline)
            readtoken(reader)
            return token
        elseif token.kind == :single_bracket_left
            readtoken(reader)
            emit(token)
            push!(stack, :inline_array)
            return TOKEN_INLINE_ARRAY_BEGIN
        elseif token.kind == :single_bracket_right
            readtoken(reader)
            pop!(stack)
            if isempty(stack) || stack[end] != :inline_array
                reader.expectvalue = false
            end
            emit(TOKEN_INLINE_ARRAY_END)
            while peektoken(reader).kind ∈ (:comment, :whitespace, :newline)
                emit(readtoken(reader))
            end
            if peektoken(reader).kind == :comma
                emit(readtoken(reader))
            end
            return token
        elseif token.kind == :curly_brace_left
            readtoken(reader)
            emit(token)
            push!(stack, :inline_table)
            return TOKEN_INLINE_TABLE_BEGIN
        elseif isatomicvalue(token)
            readtoken(reader)
            while peektoken(reader).kind ∈ (:comment, :whitespace, :newline)
                emit(readtoken(reader))
            end
            if peektoken(reader).kind == :comma
                emit(readtoken(reader))
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
            emit(TOKEN_INLINE_TABLE_END)
            while peektoken(reader).kind == :whitespace
                emit(readtoken(reader))
            end
            if peektoken(reader).kind == :comma
                emit(readtoken(reader))
            end
            return token
        elseif token.kind ∈ (:bare_key, :quoted_key)
            parsekeyvalue(reader)
            if peektoken(reader).kind == :whitespace
                emit(readtoken(reader))
            end
            if peektoken(reader).kind == :comma
                emit(readtoken(reader))
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
            emit(readtoken(reader))
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
        emit(token)
        let token = readtoken(reader)
            token.kind == :whitespace && (emit(token); token = readtoken(reader))
            if token.kind ∈ (:bare_key, :quoted_key)
                emit(token)
                peektoken(reader).kind == :whitespace && emit(readtoken(reader))
            else
                unexpectedtoken(token, reader.linenum)
            end
            while (token = readtoken(reader)).kind != close
                if token.kind == :dot
                    emit(token)
                else
                    unexpectedtoken(token, reader.linenum)
                end
                token = readtoken(reader)
                token.kind == :whitespace && (emit(token); token = readtoken(reader))
                if token.kind ∈ (:bare_key, :quoted_key)
                    emit(token)
                    peektoken(reader).kind == :whitespace && emit(readtoken(reader))
                else
                    unexpectedtoken(token, reader.linenum)
                end
            end
            if token.kind != close
                unexpectedtoken(token, reader.linenum)
            end
            emit(token)
        end
        if token.kind == :single_bracket_left
            emit(TOKEN_TABLE_END)
            return TOKEN_TABLE_BEGIN
        else
            emit(TOKEN_ARRAY_END)
            return TOKEN_ARRAY_BEGIN
        end
    else
        unexpectedtoken(token, reader.linenum)
    end
end

function parsekeyvalue(reader::StreamReader)
    # (bare_key | quoted_key) whitespace? '=' whitespace? (atomic_value | '[' | '{')
    emit(token) = push!(reader.parsequeue, token)
    emitkey = false
    @label readkey
    token = readtoken(reader)
    if !iskey(token)
        unexpectedtoken(token, reader.linenum)
    elseif emitkey
        emit(token)
    end
    token = readtoken(reader)
    if token.kind == :whitespace
        emit(token)
        token = readtoken(reader)
    end
    if token.kind == :equal
        emit(token)
    elseif token.kind == :dot
        # dotted keys
        emit(token)
        if peektoken(reader).kind == :whitespace
            emit(readtoken(reader))
        end
        emitkey = true
        @goto readkey
    else
        unexpectedtoken(token, reader.linenum)
    end
    token = readtoken(reader)
    if token.kind == :whitespace
        emit(token)
        token = readtoken(reader)
    end
    if isatomicvalue(token)
        emit(token)
        return token
    elseif token.kind == :single_bracket_left  # inline array
        emit(TOKEN_INLINE_ARRAY_BEGIN)
        emit(token)
        push!(reader.stack, :inline_array)
        return token
    elseif token.kind == :curly_brace_left  # inline table
        emit(TOKEN_INLINE_TABLE_BEGIN)
        emit(token)
        push!(reader.stack, :inline_table)
        return token
    else
        unexpectedtoken(token, reader.linenum)
    end
end

# Infer the type of elements in the current array.
function arraytype(reader::StreamReader)
    t = Any
    token = parsetoken(reader)
    tokens = [token]
    while token.kind != :inline_array_end && t == Any
        if isatomicvalue(token)
            if issigned(token)
                t = Int
            elseif isunsigned(token)
                t = UInt
            elseif isfloat(token)
                t = Float64
            elseif isstring(token)
                t = String
            elseif isboolean(token)
                t = Bool
            else
                assert(false)
            end
        elseif token.kind == :inline_array_begin
            t = Vector
        elseif token.kind == :inline_table_begin
            t = Dict{String}
        else
            # ignore
        end
        token = parsetoken(reader)
        push!(tokens, token)
    end
    prepend!(reader.parsequeue, tokens)
    return t
end

parse(str::AbstractString) = parse(IOBuffer(str))
parsefile(filename::AbstractString) = open(parse, filename)

const Table = Dict{String,Any}

function parse(input::IO)
    root = Table()
    reader = StreamReader(input)
    key = nothing
    node = root
    stack = []
    while (token = parsetoken(reader)).kind != :eof
        if iskey(token)
            key = keyname(token)
        elseif isatomicvalue(token)
            if node isa Array
                x = value(token)
                if !isempty(node) && typeof(node[1]) != typeof(x)
                    # This line number may be wrong.
                    parse_error("mixed array types", reader.linenum)
                end
                push!(node, x)
            else
                @assert !haskey(node, key)  # TODO: must be checked by the stream reader
                node[key] = value(token)
            end
        elseif token.kind == :inline_array_begin
            push!(stack, node)
            if node isa Array
                push!(node, arraytype(reader)[])
                node = node[end]
            else
                @assert !haskey(node, key)
                node[key] = arraytype(reader)[]
                node = node[key]
            end
        elseif token.kind == :inline_array_end
            node = pop!(stack)
        elseif token.kind == :inline_table_begin
            push!(stack, node)
            if node isa Array
                push!(node, Table())
                node = node[end]
            else
                @assert !haskey(node, key)
                node[key] = Table()
                node = node[key]
            end
        elseif token.kind == :inline_table_end
            node = pop!(stack)
        elseif token.kind == :table_begin  # [foo.bar]
            node = root
            while (token = parsetoken(reader)).kind != :table_end
                if iskey(token)
                    node = get!(node, keyname(token), Table())
                    if node isa Array
                        node = node[end]
                    end
                end
            end
            key = nothing
        elseif token.kind == :array_begin  # [[foo.bar]]
            node = root
            keys = String[]
            while (token = parsetoken(reader)).kind != :array_end
                if iskey(token)
                    push!(keys, keyname(token))
                end
            end
            for i in 1:length(keys)-1
                node = get!(node, keys[i], Table())
                if node isa Array
                    node = node[end]
                end
            end
            node = push!(get!(node, keys[end], []), Table())[end]
            key = nothing
        else
            # ignore
        end
    end
    return root
end
