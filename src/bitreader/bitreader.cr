module BitReader
  class BitReader
    property r : IO
    property buf : Bytes
    property x : UInt8 = 0
    property n : UInt32 = 0

    def initialize(f : IO)
      @r = f
      @buf = Bytes.new(8)
      @n = 0
    end

    def read(n : UInt8) : UInt64
      x = 0_u64
      if n == 0
        return 0_u64
      end
      if n > 64
        raise("invalid number of bits; n (#{n}) exceeds 64")
      end
      if @n > 0
        case true
        when @n == n
          @n = 0
          return @x.to_u64
        when @n > n
          @n -= n
          mask = 0xFF_u8 << @n
          x = (@x&mask).to_u64 >> @n
          @x = @x ^ @x & mask
          return x
        end
        n -= @n
        x = @x.to_u64
        @n = 0
      end
      bytes = (n / 8).to_u64
      bits = n % 8
      if bits > 0
        bytes += 1
      end

      @r.read_fully(@buf[...bytes])

      if bytes > 1
        @buf[...bytes-1].each do |b|
          x <<= 8
          x |= b.to_u64
        end
      end

      b = @buf[bytes-1]
      if bits > 0
        x <<= bits
        @n = 8_u32 - bits
        mask = 0xFF_u8 << @n
        x |= (b&mask).to_u64 >> @n
        @x = b ^ b & mask
      else
        x <<= 8   
        x |= b.to_u64
      end
    return x
    end
  end
end
