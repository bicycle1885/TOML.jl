module TOML

using Dates

include("buffer.jl")
include("value.jl")
include("token.jl")
include("tokenizer.jl")
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

end # module

