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
    array() = []
    root = table()
    reader = StreamReader(IOBuffer(str))
    key = nothing
    node = root
    while (token = parsetoken(reader)).kind != :eof
        if iskey(token)
            key = keyname(token)
        elseif isatomicvalue(token)
            node[key] = value(token)
        elseif token.kind == :table_begin  # [foo.bar]
            node = root
            while (token = parsetoken(reader)).kind != :table_end
                if iskey(token)
                    node = get!(node, keyname(token), table())
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
                node = get!(node, keys[i], table())
                if node isa Array
                    node = node[end]
                end
            end
            node = push!(get!(node, keys[end], array()), table())[end]
            key = nothing
        else
            # ignore
        end
    end
    return root
end

end # module

