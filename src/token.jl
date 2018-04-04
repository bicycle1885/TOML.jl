# Token
# =====

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
isinteger(token::Token) = token.kind == :decimal || token.kind == :binary || token.kind == :octal || token.kind == :hexadecimal
isfloat(token::Token) = token.kind == :float
isboolean(token::Token) = token.kind == :boolean
isdatetime(token::Token) = token.kind == :datetime || token.kind == :local_datetime || token.kind == :local_date || token.kind == :local_time
isatomicvalue(token::Token) = isstring(token) || isinteger(token) || isfloat(token) || isboolean(token) || isdatetime(token)
iscontainer(token::Token) = token.kind ∈ (:single_bracket_left, :curly_brace_left)
#iscontainer(token::Token) = token.kind ∈ (:inline_table_begin , :inline_array_begin)
iskey(token::Token) = token.kind == :bare_key || token.kind == :quoted_key
iseof(token::Token) = token.kind == :eof

# Human-readable description of token.
function tokendesc(token::Token)
    if isstring(token)
        return "string"
    elseif token.kind == :decimal
        return "decimal integer"
    elseif token.kind == :binary
        return "binary integer"
    elseif token.kind == :octal
        return "octal integer"
    elseif token.kind == :hexadecimal
        return "hexadecimal integer"
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
        if token.text[1] == '"'
            return unwrap_basic_string(token.text)
        else
            return unwrap_literal_string(token.text)
        end
    else
        throw(ArgumentError("not a key token"))
    end
end

# Get the value.
function value(token::Token)
    if token.kind == :decimal
        return Base.parse(Int, drop(token.text, '_'))
    elseif token.kind == :binary
        return Base.parse(UInt, drop(token.text[3:end], '_'), base=2)
    elseif token.kind == :octal
        return Base.parse(UInt, drop(token.text[3:end], '_'), base=8)
    elseif token.kind == :hexadecimal
        return Base.parse(UInt, drop(token.text[3:end], '_'), base=16)
    elseif token.kind == :float
        return Base.parse(Float64, drop(token.text, '_'))
    elseif token.kind == :boolean
        return token.text[1] == 't' ? true : false
    elseif token.kind == :basic_string
        return unwrap_basic_string(token.text)
    elseif token.kind == :multiline_basic_string
        return trimwhitespace(normnewlines(chop(token.text, head=3, tail=3)))
    elseif token.kind == :literal_string
        return unwrap_literal_string(token.text)
    elseif token.kind == :multiline_literal_string
        return normnewlines(chop(token.text, head=3, tail=3))
    elseif token.kind == :datetime
        date = Base.parse(Date, token.text[1:10], dateformat"y-m-d")
        timepart = findfirst(r"\d{2}:\d{2}:\d{2}(?:\.\d+)?", token.text)
        @assert timepart != nothing
        if length(timepart) == 8
            time = Base.parse(Time, token.text[timepart], dateformat"H:M:S")
        else
            time = Base.parse(Time, token.text[timepart], dateformat"H:M:S.s")
        end
        # return time offset as a string
        offset = token.text[timepart[end]+1:end]
        return DateTime(year(date), month(date), day(date), hour(time), minute(time), second(time), millisecond(time)), offset
    else
        throw(ArgumentError("not a value token: $(token)"))
    end
end

# utilities
function unwrap_basic_string(s::String)
    return unescape_string(chop(s, head=1, tail=1))
end
unwrap_literal_string(s::String) = String(chop(s, head=1, tail=1))
drop(s, c) = replace(s, c => "")
normnewlines(s) = replace(replace(s, r"\r" => ""), r"^\n" => "")
trimwhitespace(s) = replace(s, r"(?:^\r?\n)|(?:\\\s+)" => "")
countlines(token::Token) = count(isequal('\n'), token.text)
