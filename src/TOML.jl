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
    root = Dict{String,Any}()
    reader = StreamReader(IOBuffer(str))
    path = String[]
    while (token = parsetoken(reader)).kind != :eof
        if iskey(token)
            push!(path, keyname(token))
        elseif isatomicvalue(token)
            node = root
            for i in 1:length(path)-1
                node = get!(node, path[i], Dict{String,Any}())
            end
            node[path[end]] = value(token)
            pop!(path)
        else
            # ignore
        end
    end
    return root
end

end # module

