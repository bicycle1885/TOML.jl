# Buffer
# ======

mutable struct Buffer
    data::Vector{UInt8}
    p::Int
    p_end::Int
    p_fill::Int
    p_eof::Int

    function Buffer()
        data = Vector{UInt8}(undef, 16)
        return new(data, 1, 0, 0, -1)
    end
end

function fillbuffer!(input::IO, buffer::Buffer)
    if buffer.p_eof ≥ 0
        return 0
    end
    if (len = buffer.p_fill - buffer.p + 1) > 0
        copyto!(buffer.data, 1, buffer.data, buffer.p, len)
        buffer.p_fill -= buffer.p - 1
        buffer.p = 1
        if buffer.p_eof != -1
            buffer.p_eof -= len
        end
    end
    n::Int = length(buffer.data) - buffer.p_fill
    if n == 0
        resize!(buffer.data, length(buffer.data) * 2)
        n = length(buffer.data) - buffer.p_fill
    end
    if eof(input)
        n = 0
        buffer.p_end = buffer.p_eof = buffer.p_fill
        return n
    else
        n = min(n, bytesavailable(input))
        unsafe_read(input, pointer(buffer.data, buffer.p_fill + 1), n)
        buffer.p_fill += n
    end
    # align UTF-8 boundary
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
    return n
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
    # TODO: encoding check
    if buffer.p + offset > buffer.p_end
        fillbuffer!(input, buffer)
    end
    ensurebytes!(input, buffer, offset+4)
    #@show buffer.p, buffer.p_end, offset
    p = buffer.p + offset
    if p ≤ buffer.p_end
        b = buffer.data[p]
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
        elseif b ≤ 0b11110111
            u |= UInt32(buffer.data[buffer.p+offset+1]) << 16
            u |= UInt32(buffer.data[buffer.p+offset+2]) <<  8
            u |= UInt32(buffer.data[buffer.p+offset+3])
            return reinterpret(Char, u), 4
        end
    else
        return nothing
    end
    @label utf8error
    parse_error("invalid UTF8 sequence")
end

function scanwhile(f::Function, input::IO, buffer::Buffer; offset::Int=0)
    o = offset
    while (char_n = peekchar(input, buffer, offset=o)) != nothing
        char, n = char_n
        if !f(char)
            break
        end
        o += n
    end
    return o - offset
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
