module TOML

include("buffer.jl")
include("value.jl")
include("token.jl")
include("parser.jl")

function debug(str::AbstractString)
    tokens = Token[]
    reader = StreamReader(IOBuffer(str))
    lasttoken = nothing
    while true
        try
            token = parsetoken(reader)
            #println(token)
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
