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
    table() = Dict{String,Any}()
    root = table()
    reader = StreamReader(IOBuffer(str))
    key = ""
    node = root
    while (token = parsetoken(reader)).kind != :eof
        if iskey(token)
            key = keyname(token)
            node[key] = table()
        elseif isatomicvalue(token)
            node[key] = value(token)
        elseif token.kind == :table_begin
            node = root
            while (token = parsetoken(reader)).kind != :table_end
                if iskey(token)
                    key = keyname(token)
                    node = get!(node, key, table())
                end
            end
        else
            # ignore
        end
    end
    return root
end

end # module

