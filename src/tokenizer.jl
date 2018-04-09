# Tokenizer
# =========

mutable struct Tokenizer{S<:IO}
    # input stream
    input::S
    # data buffer
    buffer::Buffer
    # current line number
    linenum::Int
    # next token (if any)
    next::Union{Tuple{Token,Bool,Int},Nothing}
end

function Tokenizer(input::IO)
    return Tokenizer(input, Buffer(), 1, nothing)
end

isnoneol(char::Char) = ' ' ≤ char ≤ '\U10FFFF' || char == '\t'
iswhitespace(char::Char) = char == ' ' || char == '\t'
isbarekeychar(char::Char) = 'A' ≤ char ≤ 'Z' || 'a' ≤ char ≤ 'z' || '0' ≤ char ≤ '9' || char == '-' || char == '_'

# When rhs=true, it prefers right-hand side tokens to other tokens
# (e.g. "true" will be a boolean value rather than a bare key).
function readtoken(tokenizer::Tokenizer; rhs::Bool=false)::Token
    if tokenizer.next != nothing
        if tokenizer.next[2] == rhs
            token = tokenizer.next[1]
            tokenizer.next = nothing
            return token
        end
        reset(tokenizer)
    end
    input = tokenizer.input
    buffer = tokenizer.buffer
    char, w = peekchar(input, buffer)
    if w == 0
        # no more data
        return TOKEN_EOF
    end
    if iswhitespace(char)  # whitespace
        n = scanwhitespace(input, buffer)
        if n == 1
            consume!(buffer, 1)
            if char == ' '
                return TOKEN_WHITESPACE_SPACE
            else @assert char == '\t'
                return TOKEN_WHITESPACE_TAB
            end
        else
            return Token(:whitespace, taketext!(buffer, n))
        end
    elseif char == '\r' || char == '\n'
        if char == '\r'  # CR+LF
            if peekchar(input, buffer, offset=1)[1] == '\n'
                consume!(buffer, 2)
                tokenizer.linenum += 1
                return TOKEN_NEWLINE_CRLF
            else
                return Token(:unknown, "\r")
            end
        else
            consume!(buffer, 1)
            tokenizer.linenum += 1
            return TOKEN_NEWLINE_LF
        end
    elseif char == '#'  # comment
        n = scanwhile(isnoneol, input, buffer)
        return Token(:comment, taketext!(buffer, n))
    elseif char == '='
        consume!(buffer, 1)
        return TOKEN_EQUAL
    elseif !rhs && isbarekeychar(char)
        n = scanbarekey(input, buffer)
        return Token(:bare_key, taketext!(buffer, n))
    elseif !rhs && (char == '"' || char == '\'')  # quoted key
        n = scanpattern(char == '"' ? RE_BASIC_STRING : RE_LITERAL_STRING, input, buffer)
        if n < 2
            return Token(:unknown, char == '"' ? "\"" : "'")
        end
        return Token(:quoted_key, taketext!(buffer, n))
    elseif char == '.'  # dot
        consume!(buffer, 1)
        return TOKEN_DOT
    elseif char == ','  # comma
        consume!(buffer, 1)
        return TOKEN_COMMA
    elseif char == '['  # table or array of tables
        if !rhs && peekchar(input, buffer, offset=1)[1] == '['
            consume!(buffer, 2)
            return TOKEN_DOUBLE_BRACKETS_LEFT
        else
            consume!(buffer, 1)
            return TOKEN_SINGLE_BRACKET_LEFT
        end
    elseif char == ']'
        if !rhs && peekchar(input, buffer, offset=1)[1] == ']'
            consume!(buffer, 2)
            return TOKEN_DOUBLE_BRACKETS_RIGHT
        else
            consume!(buffer, 1)
            return TOKEN_SINGLE_BRACKET_RIGHT
        end
    elseif char == '{'  # inline table begin
        consume!(buffer, 1)
        return TOKEN_CURLY_BRACE_LEFT
    elseif char == '}'  # inline table end
        consume!(buffer, 1)
        return TOKEN_CURLY_BRACE_RIGHT
    else  # value
        kind, n = scanvalue(input, buffer)
        if kind == :novalue
            return Token(:unknown, taketext!(buffer, w))
        else
            text = taketext!(buffer, n)
            if kind ∈ (:multiline_basic_string, :multiline_literal_string)
                tokenizer.linenum += count(isequal('\n'), text)
            end
            return Token(kind, text)
        end
    end
end

function peektoken(tokenizer::Tokenizer; rhs::Bool=false)::Token
    if tokenizer.next == nothing
        linenum = tokenizer.linenum
        tokenizer.next = (readtoken(tokenizer, rhs=rhs), rhs, linenum)
    elseif tokenizer.next[2] != rhs && !isempty(tokenizer.next[1].text)
        reset(tokenizer)
        linenum = tokenizer.linenum
        tokenizer.next = (readtoken(tokenizer, rhs=rhs), rhs, linenum)
    end
    return tokenizer.next[1]
end

function reset(tokenizer::Tokenizer)
    @assert tokenizer.next != nothing
    takeback!(tokenizer.buffer, tokenizer.next[1].text)
    tokenizer.linenum = tokenizer.next[3]
    tokenizer.next = nothing
    return
end
