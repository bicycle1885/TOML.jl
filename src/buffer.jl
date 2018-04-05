# Buffer
# ======

const INIT_BUFFER_SIZE = Ref(256)

mutable struct Buffer
    # UTF-8 encoded sequence + 0-3 incomplete bytes
    data::Vector{UInt8}
    # the current reading position (the first byte of the UTF-8 sequence)
    p::Int
    # the end position of the UTF-8 sequence
    p_end::Int
    # the end position of the filled bytes
    p_fill::Int
    # the end position of the stream (-1 if yet found)
    p_eof::Int

    function Buffer()
        data = Vector{UInt8}(undef, INIT_BUFFER_SIZE[])
        return new(data, 1, 0, 0, -1)
    end
end

function fillbuffer!(input::IO, buffer::Buffer)
    if buffer.p_eof ≥ 0
        return 0
    end
    if buffer.p < buffer.p_fill
        # move data
        shift = buffer.p - 1
        copyto!(buffer.data, 1, buffer.data, buffer.p, buffer.p_fill - buffer.p + 1)
        buffer.p = 1
        buffer.p_end -= shift
        buffer.p_fill -= shift
    end
    if eof(input)
        # found EOF
        buffer.p_end = buffer.p_eof = buffer.p_fill
        return 0
    end
    n_avail = bytesavailable(input)
    n_free = length(buffer.data) - buffer.p_fill
    if n_free == 0  # no space to fill data
        resize!(buffer.data, length(buffer.data) * 2)
        n_free = length(buffer.data) - buffer.p_fill
    end
    # fill data into the buffer
    n = min(n_avail, n_free)
    unsafe_read(input, pointer(buffer.data, buffer.p_fill + 1), n)
    buffer.p_fill += n
    # align p_end to a UTF-8 boundary
    p_new = buffer.p_end + 1
    buffer.p_end = buffer.p_fill
    if buffer.data[buffer.p_end] ≤ 0b01111111
        # ascii
    else
        (buffer.data[buffer.p_end] >> 6) == 0b10 && (buffer.p_end -= 1)
        (buffer.data[buffer.p_end] >> 6) == 0b10 && (buffer.p_end -= 1)
        (buffer.data[buffer.p_end] >> 6) == 0b10 && (buffer.p_end -= 1)
        if buffer.p_fill == buffer.p_end + leading_ones(buffer.data[buffer.p_end])
            buffer.p_end = buffer.p_fill
        else
            buffer.p_end -= 1
        end
    end
    # validate UTF-8 encoding
    if buffer.p_end > p_new && !is_valid_utf8(buffer.data, p_new, buffer.p_end)
        throw(ErrorException("invalid UTF-8 sequence"))
    end
    return n
end

function is_valid_utf8(data::Vector{UInt8}, from::Int, to::Int)
    return ccall(:u8_isvalid, Cint, (Ptr{UInt8}, Csize_t), pointer(data, from), to - from + 1) > 0
end

function ensurebytes!(input::IO, buffer::Buffer, n::Int)
    if buffer.p_end - buffer.p + 1 ≥ n
        # ok
        return true
    end
    fillbuffer!(input, buffer)
    return buffer.p_end - buffer.p + 1 ≥ n
end

function peekchar(input::IO, buffer::Buffer; offset::Int=0)
    ensurebytes!(input, buffer, offset+4)
    if buffer.p + offset ≤ buffer.p_end
        # NOTE: UTF-8 encoding is validated in fillbuffer!
        b = buffer.data[buffer.p+offset]
        u = UInt32(b) << 24
        if b < 0b10000000
            return reinterpret(Char, u), 1
        elseif b ≤ 0b11011111
            u |= UInt32(buffer.data[buffer.p+offset+1]) << 16
            return reinterpret(Char, u), 2
        elseif b ≤ 0b11101111
            u |= UInt32(buffer.data[buffer.p+offset+1]) << 16
            u |= UInt32(buffer.data[buffer.p+offset+2]) <<  8
            return reinterpret(Char, u), 3
        else @assert b ≤ 0b11110111
            u |= UInt32(buffer.data[buffer.p+offset+1]) << 16
            u |= UInt32(buffer.data[buffer.p+offset+2]) <<  8
            u |= UInt32(buffer.data[buffer.p+offset+3])
            return reinterpret(Char, u), 4
        end
    else
        # no more character
        return '\0', 0
    end
end

function scanwhile(f::Function, input::IO, buffer::Buffer; offset::Int=0)
    o = offset
    while (char_n = peekchar(input, buffer, offset=o))[2] > 0
        char, n = char_n
        if !f(char)
            break
        end
        o += n
    end
    return o - offset
end

# Specialized function for scanning whitespace.
# Equivalent to `scanwhile(iswhitespace, input, buffer)`.
function scanwhitespace(input::IO, buffer::Buffer)
    # space or tab
    iswhitespace(b) = (b == 0x20) | (b == 0x09)
    n = 0
    @label scan
    while buffer.p + n ≤ buffer.p_end
        @inbounds if !iswhitespace(buffer.data[buffer.p+n])
            break
        end
        n += 1
    end
    if buffer.p + n > buffer.p_end && buffer.p_eof < 0 && fillbuffer!(input, buffer) > 0
        @goto scan
    end
    return n
end

# Specialized function for scanning bare keys.
# Equivalent to `scanwhile(iskeychar, input, buffer)`.
function scanbarekey(input::IO, buffer::Buffer)
    # [0-9A-Za-z-_]
    isbarekey(b) = (b == 0x2d) | (0x30 ≤ b ≤ 0x39) | (0x41 ≤ b ≤ 0x5a) | (b == 0x5f) | (0x61 ≤ b ≤ 0x7a)
    n = 0
    @label scan
    while buffer.p + n ≤ buffer.p_end
        @inbounds if !isbarekey(buffer.data[buffer.p+n])
            break
        end
        n += 1
    end
    if buffer.p + n > buffer.p_end && buffer.p_eof < 0 && fillbuffer!(input, buffer) > 0
        @goto scan
    end
    return n
end

function taketext!(buffer::Buffer, size::Int)
    text = String(buffer.data[buffer.p:buffer.p+size-1])
    buffer.p += size
    return text
end

function consume!(buffer::Buffer, size::Int)
    buffer.p += size
    return
end
