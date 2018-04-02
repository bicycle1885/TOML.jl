import Base.PCRE

# Need UTF-8 validation.
const COMPILE_OPTIONS = PCRE.UTF | PCRE.ALT_BSUX | PCRE.EXTENDED
const MATCH_OPTIONS   = PCRE.PARTIAL_SOFT

const RE_BASIC_STRING = Regex(raw"""
^
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
    \\u[0-9A-Fa-f]{4} | \\U[0-9A-Fa-f]{8}
)*?
"
""", COMPILE_OPTIONS, MATCH_OPTIONS)

const RE_MULTILINE_BASIC_STRING = Regex(raw"""
^
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
    \\u[0-9A-Fa-f]{4} | \\U[0-9A-Fa-f]{8}
)*?
\"\"\"
""", COMPILE_OPTIONS, MATCH_OPTIONS)

const RE_LITERAL_STRING = Regex(raw"""
^
'
    # non-control character
    [^\x00-\x1f]*?
'
""", COMPILE_OPTIONS, MATCH_OPTIONS)

const RE_MULTILINE_LITERAL_STRING = Regex(raw"""
^
'''
    # non-control character
    [^\x00-\x1f]*?
'''
""", COMPILE_OPTIONS, MATCH_OPTIONS)

const RE_INTEGER = Regex(raw"""
^[-+]?(?:0|[1-9](?:_?[0-9]+)*)
""", COMPILE_OPTIONS, MATCH_OPTIONS)

const RE_FLOAT = Regex(raw"""
^
(?:
    # exponent
    [-+]? (?:0|[1-9](?:_?[0-9]+)*) (?:\.[0-9](?:_?[0-9]+)*)? [eE] [-+]? (?:0|[1-9](?:_?[0-9]+)*) |
    # fractional
    [-+]? (?:0|[1-9](?:_?[0-9]+)*)    \.[0-9](?:_?[0-9]+)*
)
""", COMPILE_OPTIONS, MATCH_OPTIONS)

const RE_BOOLEAN = Regex(raw"true|false", COMPILE_OPTIONS, MATCH_OPTIONS)

const RE_DATETIME = Regex(raw"""
^
# full date
[0-9]{4}-[0-9]{2}-[0-9]{2}
# the 'T'
T
# partial time
[0-9]{2}:[0-9]{2}:[0-9]{2} (?:\.[0-9]+)?
# time offset
(?:Z|[+-][0-9]{2}:[0-9]{2})
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
        end
        n = scanpattern(RE_INTEGER, input, buffer)
        if n ≥ 0
            return :integer, n
        end
    elseif b1 == UInt8('t') || b1 == UInt8('f')
        # boolean?
        n = scanpattern(RE_BOOLEAN, input, buffer)
        if n ≥ 0
            return :boolean, n
        end
    end
    return :novalue, 0
end

#const ERROR_NOMATCH = Cint(-1)
const ERROR_PARTIAL = Cint(-2)

function scanpattern(re::Regex, input::IO, buffer::Buffer)
    if buffer.p > buffer.p_end
        fillbuffer!(input, buffer)
    end
    @label match
    #@show buffer.data[buffer.p:buffer.p_end]
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