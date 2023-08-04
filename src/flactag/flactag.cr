require "file_utils"
require "../bitreader/*"

module FLACTag
  class FLAC
    property f : IO

    def close() : Nil
      @f.close
    end

    private def check_header() : Nil
      magic = @f.read_string(4)
      if magic != "fLaC"
        raise(
          InvalidMagicException.new("file header is corrupted or not a flac file")
        )
      end
      byte = @f.read_byte()
      block_type = byte.try { |t| t & 0x7F }
      if block_type != 0x0
        raise(
          IncorrectFirstBlockException.new("first block must be stream info")
        )
      end
    end

    def initialize(flac_path : String)
      @f = File.open(flac_path, "rb")
      begin
        check_header()
      rescue ex
        @f.close
        raise(ex)
      end
      @flac_path = flac_path
    end

    private def to_be_u24(buf : Bytes) : Int32
      arr = StaticArray(UInt8, 4).new(0)
      arr[1] = buf[0]
      arr[2] = buf[1]
      arr[3] = buf[2]
      IO::ByteFormat::BigEndian.decode(Int32, arr.to_slice)
    end

    private def read_le_u32() : UInt32
      @f.read_bytes(UInt32, IO::ByteFormat::LittleEndian)
    end

    private def read_be_u32() : UInt32
      @f.read_bytes(UInt32, IO::ByteFormat::BigEndian)
    end

    private def parse_vorb_block(tags : FLACTags) : Nil
      @f.seek(3, IO::Seek::Current)
      vendor_len = read_le_u32()
      if vendor_len > 0
        vendor = @f.read_string(vendor_len)
        tags.vendor = vendor
      end
      com_count = read_le_u32()
      (0...com_count).each do
        com_len = read_le_u32()
        com = @f.read_string(com_len)
        com_split = com.split("=", 2)
        if com_split.size < 2
          raise InvalidVorbisCommentException.new("vorbis comment must have at least one '='")
        end
        field = com_split[0].downcase
        val = com_split[1]
        tags.update(field, val)
      end
    end

    private def parse_pic_block(tags : FLACTags) : Nil
      cover = FLACPicture.new
      @f.seek(3, IO::Seek::Current)
      pic_type = read_be_u32()
      mime_len = read_be_u32()
      mime_type = @f.read_string(mime_len)
      desc_len = read_be_u32()
      if desc_len > 0
        description = @f.read_string(desc_len)
        cover.description = description
      end
      width = read_be_u32()
      height = read_be_u32()
      depth = read_be_u32()
      colours_num = read_be_u32()
      data_len = read_be_u32()
      cover_buf = Bytes.new(data_len)
      @f.read_fully(cover_buf)
      
      cover.data = cover_buf
      cover.colours_num = colours_num.to_i32
      cover.depth = depth.to_i32
      cover.height = height.to_i32
      cover.width = width.to_i32
      cover.type = PictureType.new(pic_type.to_i32)
      cover.mime_type = mime_type
      tags.pictures.push(cover)
    end

    private def skip() : Nil
      buf = Bytes.new(3)
      @f.read_fully(buf)
      size = to_be_u24(buf)
      @f.seek(size, IO::Seek::Current)
    end

    def read() : FLACTags
      tags = FLACTags.new
      @f.seek(4, IO::Seek::Set)
      while b = f.read_byte()
        block_type = b.try { |t| t & 0x7F }
        case block_type
        when 0x4
          parse_vorb_block(tags)
        when 0x6
          parse_pic_block(tags)      
        else
          skip
        end
        last = 1 & (b >> 7) == 1
        if last
          break
        end
      end
      return tags
    end

    def read_stream_info() : FLACStreamInfo
      @f.seek(8, IO::Seek::Set)
      br = BitReader::BitReader.new(@f)
      block_size_min = br.read(16)
      block_size_max = br.read(16)
      frame_size_min = br.read(24)
      frame_size_max = br.read(24)
      sample_rate = br.read(20)
      channel_count = br.read(3)
      bit_depth = br.read(5)
      sample_count = br.read(36)
      audio_md5_buf = Bytes.new(16)
      @f.read_fully(audio_md5_buf)
      FLACStreamInfo.new(
        block_size_min: block_size_min.to_i16,
        block_size_max: block_size_max.to_i16,
        frame_size_min: frame_size_min.to_i32,
        frame_size_max: frame_size_max.to_i32, 
        sample_rate:    sample_rate.to_i32,  
        channel_count:  channel_count.to_i8+1,
        bit_depth:      bit_depth.to_i8+1,
        sample_count:   sample_count.to_i64,
        audio_md5:      audio_md5_buf
      )
    end

    private class Block
      property type : UInt8
      property data : Bytes
      def initialize(@type, @data)
      end
    end

    private class Blocks
      property stream_blocks  : Array(Block)
      property pic_blocks    : Array(Block)
      property other_blocks  : Array(Block)

      def initialize()
        @stream_blocks = Array(Block).new
        @pic_blocks = Array(Block).new
        @other_blocks = Array(Block).new
      end
    end

    private def to_24(in_buf : Bytes) : Bytes
      out_buf = Bytes.new(3)
      out_buf[0] = in_buf[1]
      out_buf[1] = in_buf[2]
      out_buf[2] = in_buf[3]
      return out_buf
    end

    private def read_block() : Bytes
      size_buf = Bytes.new(3)
      @f.read(size_buf)
      size = to_be_u24(size_buf)
      @f.seek(-3, IO::Seek::Current)
      data_buf = Bytes.new(size+3)
      @f.read_fully(data_buf)
      return data_buf
    end

    private def get_temp_path() : String
      #fname = File.basename(@f.path)
      fname = File.basename(@flac_path)
      unix = Time.local.to_unix_ns
      File.join(Dir.tempdir, "#{fname}_tmp_#{unix}")
    end

    private def overwrite_tags(ex : FLACTags, to_write : FLACTags, del_strings : Array(String)) : FLACTags
      if "all_tags".in?(del_strings)
        ex_pics = ex.pictures
        ex_vendor = ex.vendor
        ex = FLACTags.new
        ex.pictures = ex_pics
        ex.vendor = ex_vendor
      else
        if "album".in?(del_strings)
          ex.album = ""
        end
        if "album_artist".in?(del_strings)
          ex.album_artist = ""
        end
        if "artist".in?(del_strings)
          ex.artist = ""
        end
        if "bpm".in?(del_strings)
          ex.bpm = 0
        end
        if "comment".in?(del_strings)
          ex.comment = ""
        end
        if "compilation".in?(del_strings)
          ex.compilation = nil
        end
        if "copyright".in?(del_strings)
          ex.copyright = ""
        end
        if "date".in?(del_strings)
          ex.date = ""
        end
        if "track_number".in?(del_strings) || "track".in?(del_strings)
          ex.track_number = 0
        end
        if "track_total".in?(del_strings) || "total_tracks".in?(del_strings)
          ex.track_total = 0
        end        
        if "disk_number".in?(del_strings) || "disc_number".in?(del_strings)
          ex.disc_number = 0
        end
        if "disk_total".in?(del_strings) || "disc_total".in?(del_strings)
          ex.disc_total = 0
        end
        if "encoder".in?(del_strings)
          ex.encoder = ""
        end
        if "length".in?(del_strings)
          ex.length = 0
        end
        if "genre".in?(del_strings)
          ex.genre = ""
        end
        if "isrc".in?(del_strings)
          ex.isrc = ""
        end
        if "itunes_advisory".in?(del_strings)
          ex.itunes_advisory = nil
        end
        if "lyrics".in?(del_strings)
          ex.lyrics = ""
        end
        if "performer".in?(del_strings)
          ex.performer = ""
        end
        if "publisher".in?(del_strings)
          ex.publisher = ""
        end
        if "title".in?(del_strings)
          ex.title = ""
        end
        if "upc".in?(del_strings)
          ex.upc = ""
        end
        if "vendor".in?(del_strings)
          ex.vendor = ""
        end
        if "year".in?(del_strings)
          ex.year = 0
        end
        ex.custom.keys.each do |k|
          if k.downcase.in?(del_strings)
            ex.custom.delete(k)
          end
        end
      end

      if "all_pictures".in?(del_strings)
        ex.pictures = Array(FLACPicture).new
      end

      ex.album = to_write.album if !to_write.album.empty?
      ex.album_artist = to_write.album_artist if !to_write.album_artist.empty?
      ex.artist = to_write.artist if !to_write.artist.empty?
      ex.comment = to_write.comment if !to_write.comment.empty?
      ex.publisher = to_write.publisher if !to_write.publisher.empty?
      ex.copyright = to_write.copyright if !to_write.copyright.empty?
      ex.date = to_write.date if !to_write.date.empty?
      ex.encoder = to_write.encoder if !to_write.encoder.empty?
      ex.genre = to_write.genre if !to_write.genre.empty?
      ex.isrc = to_write.isrc if !to_write.isrc.empty?
      ex.upc = to_write.upc if !to_write.upc.empty?
      ex.lyrics = to_write.lyrics if !to_write.lyrics.empty?
      ex.performer = to_write.performer if !to_write.performer.empty?
      ex.title = to_write.title if !to_write.title.empty?
      ex.vendor = to_write.vendor if !to_write.vendor.empty?

      ex.length = to_write.length if to_write.length > 0
      ex.track_number = to_write.track_number if to_write.track_number > 0
      ex.track_total = to_write.track_total if to_write.track_total > 0
      ex.disc_number = to_write.disc_number if to_write.disc_number > 0
      ex.disc_total = to_write.disc_total if to_write.disc_total > 0
      ex.year = to_write.year if to_write.year > 0
      to_write.compilation.try { |comp| ex.compilation = comp }
      to_write.bpm.try { |bpm| ex.bpm = bpm }
      to_write.itunes_advisory.try { |advisory| ex.itunes_advisory = advisory }

      to_write.custom.each do |k, v|
        if v.empty?
          ex.custom[k.upcase] = v
        end
      end

      filtered_pics = Array(FLACPicture).new

      ex.pictures.each_with_index(1) do |p, idx|
        if !"picture:#{idx}".in?(del_strings)
          filtered_pics.push(p)
        end
      end

      # Can't splat arrays.
      to_write.pictures.each do |p|
        filtered_pics.push(p)
      end

      ex.pictures = filtered_pics
      return ex
    end

    private def write_com(f : IO, field_name : String, field_val : _) : Int32
      buf = Bytes.new(4)
      pair = field_name.upcase + "=" + field_val.to_s
      pair_size = pair.size
      IO::ByteFormat::LittleEndian.encode(pair_size, buf)
      f.write(buf)
      f.print(pair)
      return pair_size + 4
    end

    private def write_pic_block(f : IO, cover : FLACPicture) : Nil
      written = 0
      buf = Bytes.new(4)
      pic_data_size = cover.data.size
      cover_desc_size = cover.description.size
      mime_type_size = cover.mime_type.size
      f.write_byte(0x06)
      block_size_p = f.tell
      f.write(Slice.new(3, 0x0_u8))

      IO::ByteFormat::BigEndian.encode(cover.type.value, buf)
      f.write(buf)
      IO::ByteFormat::BigEndian.encode(cover.mime_type.size, buf)
      f.write(buf)
      f.print(cover.mime_type)
      IO::ByteFormat::BigEndian.encode(cover_desc_size, buf)
      f.write(buf)

      written += mime_type_size + 12

      if cover_desc_size > 0
        f.print(cover.description)
        written += cover_desc_size
      end

      IO::ByteFormat::BigEndian.encode(cover.width, buf)
      f.write(buf)     
      IO::ByteFormat::BigEndian.encode(cover.height, buf)
      f.write(buf)
      IO::ByteFormat::BigEndian.encode(cover.depth, buf)
      f.write(buf)
      IO::ByteFormat::BigEndian.encode(cover.colours_num, buf)
      f.write(buf)
      IO::ByteFormat::BigEndian.encode(pic_data_size, buf)
      f.write(buf)

      written += 20

      f.write(cover.data)
      written += pic_data_size
      end_block_p = f.tell
      f.seek(block_size_p, IO::Seek::Set)
      IO::ByteFormat::BigEndian.encode(written, buf)
      written_24 = to_24(buf)
      f.write(written_24)
      f.seek(end_block_p, IO::Seek::Set)
      # return written
    end

    private def write_end(f : IO) : Nil
      # 4 MB
      buf_size = 4096*1024
      buf = Bytes.new(buf_size)
      loop do
        pos = @f.tell
        read = @f.read(buf)
        if read < 1
          break
        elsif read < buf_size
          f.write(buf[...read])
        else
          f.write(buf)
        end      
      end
    end

    private def create(parsed_blocks : Blocks, to_write : FLACTags, temp_path : String, del_strings : Array(String)) : Nil
      written = 0
      com_count = 0
      end_data_start = @f.tell
      # @f.seek(4, IO::Seek::Set)
      tags = read
      tags = overwrite_tags(tags, to_write, del_strings)

      File.open(temp_path, "wb+") do |f|
        f.print("fLaC")
        f.write_byte(0x0)
        f.write(parsed_blocks.stream_blocks[0].data)
        f.write_byte(0x4)
        p = f.tell
        f.write(Slice.new(3, 0x0_u8))

        vendor_size = tags.vendor.size
        buf = Bytes.new(4)
        IO::ByteFormat::LittleEndian.encode(vendor_size, buf)
        f.write(buf)
        written += 4
        f.print(tags.vendor)
        written += vendor_size
        com_count_p = f.tell
        f.write(Slice.new(4, 0x0_u8))
        written += 4

        if !tags.album.empty?
          written += write_com(f, "album", tags.album)
          com_count += 1
        end

        if !tags.artist.empty?
          written += write_com(f, "artist", tags.artist)
          com_count += 1
        end

        if !tags.album_artist.empty?
          written += write_com(f, "albumartist", tags.album_artist)
          com_count += 1
        end       

        if !tags.comment.empty?
          written += write_com(f, "comment", tags.comment)
          com_count += 1
        end

        if !tags.copyright.empty?
          written += write_com(f, "copyright", tags.copyright)
          com_count += 1
        end

        if !tags.date.empty?
          written += write_com(f, "date", tags.date)
          com_count += 1
        end

        if !tags.encoder.empty?
          written += write_com(f, "encoder", tags.encoder)
          com_count += 1
        end

        if !tags.genre.empty?
          written += write_com(f, "genre", tags.genre)
          com_count += 1
        end

        if !tags.isrc.empty?
          written += write_com(f, "isrc", tags.isrc)
          com_count += 1
        end

        if !tags.lyrics.empty?
          written += write_com(f, "lyrics", tags.lyrics)
          com_count += 1
        end

        if !tags.upc.empty?
          written += write_com(f, "upc", tags.upc)
          com_count += 1
        end

        if !tags.performer.empty?
          written += write_com(f, "performer", tags.performer)
          com_count += 1
        end

        if !tags.title.empty?
          written += write_com(f, "title", tags.title)
          com_count += 1
        end

        if !tags.publisher.empty?
          written += write_com(f, "publisher", tags.publisher)
          com_count += 1
        end       

        if tags.track_number > 0
          written += write_com(f, "tracknumber", tags.track_number)
          com_count += 1
        end 

        if tags.track_total > 0
          written += write_com(f, "tracktotal", tags.track_total)
          com_count += 1
        end

        if tags.disc_number > 0
          written += write_com(f, "discnumber", tags.disc_number)
          com_count += 1
        end

        if tags.disc_total > 0
          written += write_com(f, "disctotal", tags.disc_total)
          com_count += 1
        end

        tags.itunes_advisory.try { |advisory|
          if advisory > -1
            written += write_com(f, "itunesadvisory", advisory)
            com_count += 1
          end
        }

        tags.bpm.try { |bpm|
          if bpm > 0
            written += write_com(f, "bpm", bpm)
            com_count += 1
          end
        }

        tags.compilation.try { |comp|
          if comp > 0
            written += write_com(f, "compilation", comp)
            com_count += 1
          end
        }      

        tags.custom.each do |k, v|
          if v.empty?
            next
          end
          written += write_com(f, k, v)
          com_count += 1
        end

        tags.pictures.each do |c|
          write_pic_block(f, c)
        end

        parsed_blocks.other_blocks.each do |b|
          f.write_byte(b.type)
          f.write(b.data)
        end

        @f.seek(end_data_start, IO::Seek::Set)
        write_end(f)
        f.seek(com_count_p, IO::Seek::Set)
        IO::ByteFormat::LittleEndian.encode(com_count, buf)
        f.write(buf)
        IO::ByteFormat::BigEndian.encode(written, buf)
        f.seek(p, IO::Seek::Set)
        written_24 = to_24(buf)
        f.write(written_24)
      end
    end

    def write(to_write : FLACTags, _del_strings : Array(String)) : Nil
      @f.seek(4, IO::Seek::Set)
      del_strings = _del_strings.map &.downcase
      parsed_blocks = Blocks.new
      
      while b = f.read_byte
        block_type = b.try { |t| t & 0x7F }
        block_data = read_block
        block = Block.new(type: b, data: block_data)
        case block_type
        when 0x0
          parsed_blocks.stream_blocks.push(block)
        when 0x4
        when 0x6
          parsed_blocks.pic_blocks.push(block)
        else
          parsed_blocks.other_blocks.push(block)
        end
        last = 1 & (b >> 7) == 1
        if last
          break
        end
      end

      temp_path = get_temp_path
      create(parsed_blocks, to_write, temp_path, del_strings)
      @f.close
      FileUtils.rm(@flac_path)
      # mv not working between different hard drives.
      FileUtils.cp(temp_path, @flac_path)
      FileUtils.rm(temp_path)
      # File.rename(temp_path, @flac_path)
      @f = File.open(@flac_path, "rb")
    end
  end
end
