import Base.PCRE

const COMPILE_OPTIONS = PCRE.UTF | PCRE.ALT_BSUX | PCRE.EXTENDED | PCRE.NO_UTF_CHECK
const MATCH_OPTIONS   = PCRE.PARTIAL_SOFT | PCRE.NO_UTF_CHECK

const RE_BASIC_STRING = Regex(raw"""
\A
"
(?:
    # non-control, non-backslash character
    [^\x00-\x1f\\] |
    # escaped control
    \\[btnfr] |
    # escaped double-quote
    \\ "  |
    # escaped backslash
    \\ \\ |
    # escaped Unicode
    \\u[0-9A-F]{4} | \\U[0-9A-F]{8}
)*?
"
""", COMPILE_OPTIONS, MATCH_OPTIONS)

const RE_MULTILINE_BASIC_STRING = Regex(raw"""
\A
\"\"\"
(?:
    # non-control, non-backslash character
    [^\x00-\x1f\\] |
    # newline (LF or CRLF)
    \r?\n |
    # escaped control character
    \\[btnfr] |
    # escaped double quote character
    \\ " |
    # escaped backslash character
    \\ \\ |
    # escaped whitespace or newline character
    \\ (?: [ \t]+ | \r?\n) |
    # escaped Unicode codepoint
    \\u[0-9A-F]{4} | \\U[0-9A-F]{8}
)*?
\"\"\"
""", COMPILE_OPTIONS, MATCH_OPTIONS)

const RE_LITERAL_STRING = Regex(raw"""
\A
'
    # non-control character
    [^\x00-\x1f]*?
'
""", COMPILE_OPTIONS, MATCH_OPTIONS)

const RE_MULTILINE_LITERAL_STRING = Regex(raw"""
\A
'''
(?:
    # non-control character
    [^\x00-\x1f] |
    # newline (LF or CRLF)
    \r?\n
)*?
'''
""", COMPILE_OPTIONS, MATCH_OPTIONS)

const RE_BINARY = Regex(raw"""
\A0b[01](?:_?[01]+)*
""", COMPILE_OPTIONS, MATCH_OPTIONS)

const RE_OCTAL = Regex(raw"""
\A0o[0-7](?:_?[0-7]+)*
""", COMPILE_OPTIONS, MATCH_OPTIONS)

const RE_DECIMAL = Regex(raw"""
\A[-+]?(?:0|[1-9](?:_?[0-9]+)*)
""", COMPILE_OPTIONS, MATCH_OPTIONS)

const RE_HEXADECIMAL = Regex(raw"""
\A0x[0-9A-F](?:_?[0-9A-F]+)*
""", COMPILE_OPTIONS, MATCH_OPTIONS)

const RE_FLOAT = Regex(raw"""
\A
(?:
    # exponent
    [-+]? (?:0|[1-9](?:_?[0-9]+)*) (?:\.[0-9](?:_?[0-9]+)*)? [eE] [-+]? (?:0|[1-9](?:_?[0-9]+)*) |
    # fractional
    [-+]? (?:0|[1-9](?:_?[0-9]+)*)    \.[0-9](?:_?[0-9]+)* |
    # infinity
    [-+]? inf |
    # not a number
    [-+]? nan
)
""", COMPILE_OPTIONS, MATCH_OPTIONS)

const RE_BOOLEAN = Regex(raw"\A(?:true|false)", COMPILE_OPTIONS, MATCH_OPTIONS)

const RE_DATETIME = Regex(raw"""
\A
# full date
[0-9]{4}-[0-9]{2}-[0-9]{2}
# the 'T' or a space (RFC 3339 section 5.6)
[T ]
# partial time
[0-9]{2}:[0-9]{2}:[0-9]{2} (?:\.[0-9]+)?
# time offset
(?:Z|[+-][0-9]{2}:[0-9]{2})
""", COMPILE_OPTIONS, MATCH_OPTIONS)

const RE_LOCAL_DATETIME = Regex(raw"""
\A
# full date
[0-9]{4}-[0-9]{2}-[0-9]{2}
# the 'T' or a space (RFC 3339 section 5.6)
[T ]
# partial time
[0-9]{2}:[0-9]{2}:[0-9]{2} (?:\.[0-9]+)?
""", COMPILE_OPTIONS, MATCH_OPTIONS)

const RE_LOCAL_DATE = Regex(raw"""
\A
# full date
[0-9]{4}-[0-9]{2}-[0-9]{2}
""", COMPILE_OPTIONS, MATCH_OPTIONS)

const RE_LOCAL_TIME = Regex(raw"""
\A
# partial time
[0-9]{2}:[0-9]{2}:[0-9]{2} (?:\.[0-9]+)?
""", COMPILE_OPTIONS, MATCH_OPTIONS)

function scanvalue(input::IO, buffer::Buffer)
    if buffer.p > buffer.p_end
        fillbuffer!(input, buffer)
        if 0 ≤ buffer.p_eof < buffer.p
            return :eof, 0
        end
    end
    b1 = buffer.data[buffer.p]
    #@show b1
    if b1 == UInt8('"')
        # basic string?
        n = scanpattern(RE_MULTILINE_BASIC_STRING, input, buffer)
        if n ≥ 0
            return :multiline_basic_string, n
        end
        n = scanpattern(RE_BASIC_STRING, input, buffer)
        if n ≥ 0
            return :basic_string, n
        end
    elseif b1 == UInt8('\'')
        # literal string?
        n = scanpattern(RE_MULTILINE_LITERAL_STRING, input, buffer)
        if n ≥ 0
            return :multiline_literal_string, n
        end
        n = scanpattern(RE_LITERAL_STRING, input, buffer)
        if n ≥ 0
            return :literal_string, n
        end
    elseif UInt8('0') ≤ b1 ≤ UInt8('9') || b1 == UInt8('-') || b1 == UInt8('+')
        if b1 == UInt('0') && ensurebytes!(input, buffer, 2)
            b2 = buffer.data[buffer.p+1]
            if b2 == UInt8('b')
                n = scanpattern(RE_BINARY, input, buffer)
                if n ≥ 0
                    return :binary, n
                end
                @goto novalue
            elseif b2 == UInt8('o')
                n = scanpattern(RE_OCTAL, input, buffer)
                if n ≥ 0
                    return :octal, n
                end
                @goto novalue
            elseif b2 == UInt8('x')
                n = scanpattern(RE_HEXADECIMAL, input, buffer)
                if n ≥ 0
                    return :hexadecimal, n
                end
                @goto novalue
            end
        end
        # float, datetime or integer?
        n = scanpattern(RE_FLOAT, input, buffer)
        if n ≥ 0
            return :float, n
        end
        if b1 != UInt8('-') && b1 != UInt8('+')
            n = scanpattern(RE_DATETIME, input, buffer)
            if n ≥ 0
                return :datetime, n
            end
            n = scanpattern(RE_LOCAL_DATETIME, input, buffer)
            if n ≥ 0
                return :local_datetime, n
            end
            n = scanpattern(RE_LOCAL_DATE, input, buffer)
            if n ≥ 0
                return :local_date, n
            end
            n = scanpattern(RE_LOCAL_TIME, input, buffer)
            if n ≥ 0
                return :local_time, n
            end
        end
        n = scanpattern(RE_DECIMAL, input, buffer)
        if n ≥ 0
            return :decimal, n
        end
    elseif b1 == UInt8('i') || b1 == UInt('n') # inf / nan
        # float?
        n = scanpattern(RE_FLOAT, input, buffer)
        if n ≥ 0
            return :float, n
        end
    elseif b1 == UInt8('t') || b1 == UInt8('f')
        # boolean?
        n = scanpattern(RE_BOOLEAN, input, buffer)
        if n ≥ 0
            return :boolean, n
        end
    end
    @label novalue
    return :novalue, 0
end

#const ERROR_NOMATCH = Cint(-1)
const ERROR_PARTIAL = Cint(-2)

function scanpattern(re::Regex, input::IO, buffer::Buffer)
    if buffer.p > buffer.p_end
        fillbuffer!(input, buffer)
    end
    @label match
    rc = ccall(
        (:pcre2_match_8, PCRE.PCRE_LIB),
        Cint,
        (Ptr{Cvoid}, Ptr{UInt8}, Csize_t, Csize_t, Cuint, Ptr{Cvoid}, Ptr{Cvoid}),
        re.regex, pointer(buffer.data, buffer.p), buffer.p_end - buffer.p + 1, 0, re.match_options, re.match_data, PCRE.MATCH_CONTEXT[])
    if rc > 0
        len = Ref{Csize_t}(0)
        rc = ccall(
            (:pcre2_substring_length_bynumber_8, PCRE.PCRE_LIB),
            Cint,
            (Ptr{Cvoid}, UInt32, Ref{Csize_t}),
            re.match_data, 0, len)
        @assert rc == 0  # it must success
        if len[] == buffer.p_end - buffer.p + 1 && buffer.p_eof < 0
            fillbuffer!(input, buffer)
            @goto match
        else
            return Int(len[])
        end
    elseif rc == ERROR_PARTIAL && buffer.p_eof < 0
        fillbuffer!(input, buffer)
        @goto match
    else
        return -1
    end
end
