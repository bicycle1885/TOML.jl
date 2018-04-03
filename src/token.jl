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
        # FIXME
        return token.text[2:end-1]
    else
        throw(ArgumentError("not a key token"))
    end
end

# Get the value.
function value(token::Token)
    if token.kind == :decimal
        return Base.parse(Int, token.text)
    elseif token.kind == :binary
        return Base.parse(UInt, token.text[3:end], base=2)
    elseif token.kind == :octal
        return Base.parse(UInt, token.text[3:end], base=8)
    elseif token.kind == :hexadecimal
        return Base.parse(UInt, token.text[3:end], base=16)
    elseif token.kind == :float
        return Base.parse(Float64, token.text)
    elseif token.kind == :boolean
        return token.text[1] == 't' ? true : false
    elseif token.kind == :basic_string
        # TODO: support unicode escaping (\UXXXXXXXX)
        return unescape_string(chop(token.text, head=1, tail=1))
    elseif token.kind == :literal_string
        return String(chop(token.text, head=1, tail=1))
    elseif token.kind == :multiline_literal_string
        return token.text[4:end-3]
    # FIXME: datetime, strings,
    else
        throw(ArgumentError("not a value token"))
    end
end

countlines(token::Token) = count(isequal('\n'), token.text)
