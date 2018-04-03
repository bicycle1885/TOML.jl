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
        elseif char == '#'  # comment
            #n = scanwhile(c -> (@show c; c != '\r' && c != '\n'), input, buffer)
            n = scanwhile(c -> c != '\r' && c != '\n', input, buffer)
            return Token(:comment, taketext!(buffer, n))
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
            if isempty(stack) || stack[end] != :inline_array
                reader.expectvalue = false
            end
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

function readtoml(filename::AbstractString)
    return open(parsetoml, filename)
end

function parsetoml(file::IO)
    root = Dict{String,Any}()
    # stack to keep track of nested structure (:table, :array, :inline_table, or :inline_array)
    stack = Symbol[]
    top() = isempty(stack) ? :none : stack[end]
    # path to a value
    path = Union{String,Int}[]
    reader = StreamReader(file)
    while (token = parsetoken(reader)).kind != :eof
        if iskey(token)
            push!(path, keyname(token))
        elseif isatomicvalue(token)
            @show path token
            node = root
            for i in 1:length(path)-1
                if path[i] isa String
                    node = get!(node, path[i], Dict{String,Any}())
                else
                    @assert path[i] isa Int
                    node = node[path[i]]
                end
            end
            node[path[end]] = token
            pop!(path)
        elseif token.kind == :table_begin  # [foo.bar.baz]
            empty!(stack)
            push!(stack, :table)
            empty!(path)
            while (token = parsetoken(reader)).kind != :table_end
                if iskey(token)
                    push!(path, keyname(token))
                end
            end
            inittable!(root, path)
        elseif token.kind == :array_begin  # [[foo.bar.baz]]
            empty!(stack)
            push!(stack, :array)
            tmppath = String[]
            while (token = parsetoken(reader)).kind != :array_end
                if iskey(token)
                    push!(tmppath, keyname(token))
                end
            end
            @show tmppath path
            if tmppath == path[1:end-1]
                path[end] += 1
            else
                empty!(path)
                append!(path, tmppath)
                push!(path, 1)
            end
            initarray!(root, path)
        #elseif token.kind == :inline_table_begin
        #elseif token.kind == :inline_table_end
        else
            # ignore
        end
    end
    return root
end

function inittable!(node, path)
    @assert length(path) ≥ 1
    for i in 1:length(path)
        node = get!(node, path[i], Dict{String,Any}())
    end
    return node
end

function initarray!(node, path)
    @assert length(path) ≥ 2
    @assert path[end] isa Int
    for i in 1:length(path)-2
        node = get!(node, path[i], Dict{String,Any}())
    end
    node = get!(node, path[end-1], [])
    #@assert length(node) == path[end] - 1
    push!(node, Dict{String,Any}())
    return node
end
