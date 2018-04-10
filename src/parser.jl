# Parser
# ======

mutable struct StreamReader
    tokenizer::Tokenizer
    # mutable state
    stack::Vector{Symbol}
    queue::Vector{Token}
end

function StreamReader(input::IO)
    return StreamReader(Tokenizer(input), Symbol[], Token[])
end

function linenumber(reader::StreamReader)
    linenum = reader.tokenizer.linenum
    for token in reader.queue
        if token.kind == :newline
            linenum -= 1
        end
    end
    return linenum
end

struct ParseError <: Exception
    msg::String
end

parse_error(msg, linenum) = throw(ParseError("$(msg) at line $(linenum)"))
unexpectedtoken(token, linenum) = parse_error("unexpected $(tokendesc(token))", token.kind == :newline ? linenum - 1 : linenum)

# Basically, this function parses line by line.
function parsetoken(reader::StreamReader)
    if !isempty(reader.queue)
        return popfirst!(reader.queue)
    end
    top() = isempty(reader.stack) ? :__empty__ : reader.stack[end]
    emit(token) = push!(reader.queue, token)
    tokenizer = reader.tokenizer
    stack = reader.stack
    token = readtoken(tokenizer, rhs=top() == :array)
    if token.kind == :whitespace
        return token
    elseif top() == :array
        if token.kind ∈ (:newline, :comment)
            return token
        elseif isatomicvalue(token)
            let token = peektoken(tokenizer, rhs=true)
                if token.kind == :whitespace
                    emit(readtoken(tokenizer, rhs=true))
                    token = peektoken(tokenizer, rhs=true)
                end
                if token.kind == :comma
                    emit(readtoken(tokenizer, rhs=true))
                elseif token.kind ∈ (:single_bracket_right, :newline, :comment)
                    # ok
                else
                    unexpectedtoken(token, tokenizer.linenum)
                end
            end
            return token
        elseif token.kind == :single_bracket_left
            # found a new array inside the current array (nested arrays)
            push!(stack, :array)
            emit(token)
            return TOKEN_INLINE_ARRAY_BEGIN
        elseif token.kind == :curly_brace_left
            # found an inline table inside the current array
            push!(stack, :table)
            emit(token)
            return TOKEN_INLINE_TABLE_BEGIN
        elseif token.kind == :single_bracket_right
            pop!(stack)
            emit(TOKEN_INLINE_ARRAY_END)
            if top() == :array
                let token = peektoken(tokenizer, rhs=true)
                    if token.kind == :whitespace
                        emit(readtoken(tokenizer, rhs=true))
                        token = peektoken(tokenizer, rhs=true)
                    end
                    if token.kind == :comma
                        emit(readtoken(tokenizer, rhs=true))
                    elseif token.kind ∈ (:single_bracket_right, :newline, :comment)
                        # ok
                    else
                        unexpectedtoken(token, tokenizer.linenum)
                    end
                end
            elseif top() == :table
                let token = peektoken(tokenizer)
                    if token.kind == :whitespace
                        emit(readtoken(tokenizer))
                        token = peektoken(tokenizer)
                    end
                    if token.kind == :comma
                        emit(readtoken(tokenizer))
                    elseif token.kind == :curly_brace_right
                        # ok
                    else
                        unexpectedtoken(token, tokenizer.linenum)
                    end
                end
            else @assert isempty(stack)
                parselineend(reader)
            end
            return token
        else
            unexpectedtoken(token, tokenizer.linenum)
        end
    elseif top() == :table
        if iskey(token)
            let token = readtoken(tokenizer)
                # read equal sign
                if token.kind == :whitespace
                    emit(token)
                    token = readtoken(tokenizer)
                end
                if token.kind != :equal
                    unexpectedtoken(token, tokenizer.linenum)
                end
                emit(token)
                # read value
                token = readtoken(tokenizer, rhs=true)
                if token.kind == :whitespace
                    emit(token)
                    token = readtoken(tokenizer, rhs=true)
                end
                if isatomicvalue(token)
                    emit(token)
                    # read comma or right curly brace
                    token = peektoken(tokenizer)
                    if token.kind == :whitespace
                        emit(readtoken(tokenizer))
                        token = peektoken(tokenizer)
                    end
                    if token.kind == :comma
                        emit(readtoken(tokenizer))
                    elseif token.kind == :curly_brace_right
                        # ok
                    else
                        unexpectedtoken(token, tokenizer.linenum)
                    end
                elseif token.kind == :single_bracket_left
                    push!(stack, :array)
                    emit(TOKEN_INLINE_ARRAY_BEGIN)
                    emit(token)
                elseif token.kind == :curly_brace_left
                    push!(stack, :table)
                    emit(TOKEN_INLINE_TABLE_BEGIN)
                    emit(token)
                else
                    unexpectedtoken(token, tokenizer.linenum)
                end
            end
            return token
        elseif token.kind == :curly_brace_right
            pop!(stack)
            emit(TOKEN_INLINE_TABLE_END)
            if top() == :array
                let token = peektoken(tokenizer, rhs=true)
                    if token.kind == :whitespace
                        emit(readtoken(tokenizer, rhs=true))
                        token = peektoken(tokenizer, rhs=true)
                    end
                    if token.kind == :comma
                        emit(readtoken(tokenizer, rhs=true))
                    elseif token.kind ∈ (:single_bracket_right, :newline, :comment)
                        # ok
                    else
                        unexpectedtoken(token, tokenizer.linenum)
                    end
                end
            elseif top() == :table
                let token = peektoken(tokenizer)
                    if token.kind == :whitespace
                        emit(readtoken(tokenizer))
                        token = peektoken(tokenizer)
                    end
                    if token.kind == :comma
                        emit(readtoken(tokenizer))
                    elseif token.kind == :curly_brace_right
                        # ok
                    else
                        unexpectedtoken(token, tokenizer.linenum)
                    end
                end
            else @assert isempty(stack)
                parselineend(reader)
            end
            return token
        else
            unexpectedtoken(token, tokenizer.linenum)
        end
    elseif iskey(token)
        let token = readtoken(tokenizer)
            if token.kind == :whitespace
                emit(token)
                token = readtoken(tokenizer)
            end
            if token.kind != :equal
                unexpectedtoken(token, tokenizer.linenum)
            end
            emit(token)
            token = readtoken(tokenizer, rhs=true)
            if token.kind == :whitespace
                emit(token)
                token = readtoken(tokenizer, rhs=true)
            end
            if isatomicvalue(token)
                emit(token)
                parselineend(reader)
            elseif token.kind == :single_bracket_left  # <key> = [
                push!(stack, :array)
                emit(TOKEN_INLINE_ARRAY_BEGIN)
                emit(token)
            elseif token.kind == :curly_brace_left  # <key> = {
                push!(stack, :table)
                emit(TOKEN_INLINE_TABLE_BEGIN)
                emit(token)
            else
                unexpectedtoken(token, tokenizer.linenum)
            end
        end
        return token
    elseif token.kind ∈ (:single_bracket_left, :double_brackets_left)
        endkind = token.kind == :single_bracket_left ? :single_bracket_right : :double_brackets_right
        emit(token)
        token = readtoken(tokenizer)
        if token.kind == :whitespace
            emit(token)
            token = readtoken(tokenizer)
        end
        if !iskey(token)
            unexpectedtoken(token, tokenizer.linenum)
        end
        emit(token)
        while (token = readtoken(tokenizer)).kind != endkind
            if token.kind == :whitespace
                emit(token)
                token = readtoken(tokenizer)
            end
            if token.kind == endkind
                break
            elseif token.kind != :dot
                unexpectedtoken(token, tokenizer.linenum)
            end
            emit(token)
            token = readtoken(tokenizer)
            if token.kind == :whitespace
                emit(token)
                token = readtoken(tokenizer)
            end
            if !iskey(token)
                unexpectedtoken(token, tokenizer.linenum)
            end
            emit(token)
        end
        emit(token)
        emit(endkind == :single_bracket_right ? TOKEN_TABLE_END : TOKEN_ARRAY_END)
        parselineend(reader)
        return endkind == :single_bracket_right ? TOKEN_TABLE_BEGIN : TOKEN_ARRAY_BEGIN
    elseif token.kind ∈ (:newline, :comment, :eof)
        return token
    else
        unexpectedtoken(token, tokenizer.linenum)
    end
end

function parselineend(reader::StreamReader)
    emit(token) = push!(reader.queue, token)
    tokenizer = reader.tokenizer
    token = readtoken(tokenizer)
    if token.kind == :whitespace
        emit(token)
        token = readtoken(tokenizer)
        if token.kind == :comment
            emit(token)
            token = readtoken(tokenizer)
        end
    elseif token.kind == :comment
        emit(token)
        token = readtoken(tokenizer)
    end
    if !iseol(token)
        unexpectedtoken(token, tokenizer.linenum)
    end
    emit(token)
    return token
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
    prepend!(reader.queue, tokens)
    return t
end

parse(str::AbstractString) = parse(IOBuffer(str))
parsefile(filename::AbstractString) = open(parse, filename)

const Table = Dict{String,Any}

function parse(input::IO)
    reader = StreamReader(input)
    dupdef() = parse_error("found a duplicated definition", linenumber(reader))
    root = Table()
    tablekeys = Set{Vector{String}}()
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
                    parse_error("mixed array types", linenumber(reader))
                end
                push!(node, x)
            else
                haskey(node, key) && dupdef()
                node[key] = value(token)
            end
        elseif token.kind == :inline_array_begin
            push!(stack, node)
            if node isa Array
                push!(node, arraytype(reader)[])
                node = node[end]
            else
                haskey(node, key) && dupdef()
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
                haskey(node, key) && dupdef()
                node = get!(node, key, Table())
            end
        elseif token.kind == :inline_table_end
            node = pop!(stack)
        elseif token.kind == :table_begin  # [foo.bar]
            keys = String[]
            while (token = parsetoken(reader)).kind != :table_end
                iskey(token) && push!(keys, keyname(token))
            end
            node = root
            for i in 1:length(keys)
                node = get!(node, keys[i], Table())
                if node isa Table
                    # ok
                elseif node isa Array
                    node = node[end]
                else
                    dupdef()
                end
            end
            keys ∈ tablekeys && dupdef()
            push!(tablekeys, keys)
            key = nothing
        elseif token.kind == :array_begin  # [[foo.bar]]
            keys = String[]
            while (token = parsetoken(reader)).kind != :array_end
                iskey(token) && push!(keys, keyname(token))
            end
            node = root
            for i in 1:length(keys)-1
                node = get!(node, keys[i], Table())
                if node isa Table
                    # ok
                elseif node isa Array
                    node = node[end]
                else
                    dupdef()
                end
            end
            node = push!(get!(node, keys[end], Table[]), Table())[end]
            key = nothing
        else
            # ignore
        end
    end
    return root
end
