module FLACTag
  class IncorrectFirstBlockException < Exception
    end 
  class InvalidVorbisCommentException < Exception
    end
  class InvalidMagicException < Exception
    end

  class FLACStreamInfo
    property block_size_min : Int16
    property block_size_max : Int16
    property frame_size_min : Int32
    property frame_size_max : Int32
    property sample_rate    : Int32
    property channel_count  : Int8
    property bit_depth      : Int8
    property sample_count   : Int64
    property audio_md5      : Bytes

    def initialize(@block_size_min, @block_size_max, @frame_size_min,
      @frame_size_max, @sample_rate, @channel_count, @bit_depth,
      @sample_count, @audio_md5)
    end
  end

  enum PictureType : Int32
    Other
    Icon
    OtherIcon
    FrontCover
    BackCover
    Leaflet
    Media
    LeadArtist
    Artist
    Conductor
    Band
    Composer
    Lyricist
    RecordingLocation
    DuringRecording
    DuringPerformance
    VideoCapture
    Illustration
    BandLogotype
    PublisherLogotype
  end

  enum ITUNESADVISORY : UInt32
    Explicit = 1
    Clean
  end

  class FLACPicture
    property colours_num : Int32 = 0
    property depth : Int32 = 0
    property description : String = ""
    property height : Int32 = 0
    property mime_type : String = ""
    property type : PictureType = PictureType::FrontCover
    property width : Int32 = 0
    property data : Bytes = Bytes.new(0)
  end

  class FLACTags
    property pictures : Array(FLACPicture)
    property album : String = ""
    property album_artist : String = ""
    property artist : String = ""
    property bpm : Int32 = 0
    property comment : String = ""
    property compilation : Bool?
    property copyright : String = ""
    property custom : Hash(String, String)
    property date : String = ""
    property disc_number : Int32 = 0
    property disc_total : Int32 = 0
    property encoder : String = ""
    property length : Int32 = 0
    property genre : String = ""
    property isrc : String = ""
    property itunes_advisory : ITUNESADVISORY?
    property lyrics : String = ""
    property performer : String = ""
    property publisher : String = ""
    property title : String = ""
    property track_number : Int32 = 0
    property track_total : Int32 = 0
    property upc : String = ""
    property vendor : String = ""
    property year : Int32 = 0

    def initialize()
      @custom = Hash(String, String).new
      @pictures = Array(FLACPicture).new
    end

    def update(var_name : String, value : _) : Nil
      var_name = var_name.gsub("_", "")
      case var_name
      when "album"
        @album = value.to_s
      when "albumartist"
        @album_artist = value.to_s
      when "comment"
        @comment = value.to_s
      when "artist"
        @artist = value.to_s
      when "date", "year"
        if value.to_s.each_char.all? &.number?
          @year = value.to_i32
        else
          @date = value.to_s
        end
      when "bpm"
        @bpm = value.to_i32
      when "isrc"
        @isrc = value.to_s
      when "upc"
        @upc = value.to_s          
      when "lyrics"
        @lyrics = value.to_s
      when "title"
        @title = value.to_s  
      when "performer"
        @performer = value.to_s
      when "encoder"
        @encoder = value.to_s
      when "copyright"
        @copyright = value.to_s
      when "genre"
        @genre = value.to_s
      when "itunesadvisory"
        advisory = ITUNESADVISORY.new(value.to_u32)
        @itunes_advisory = advisory if ITUNESADVISORY.valid?(advisory)
      when "length"
        @length = value.to_i      
       when "compilation"
        @compilation = value.to_i32 == 1
      when "vendor"
        @vendor = value.to_s
      when "tracknumber", "track"
        track = value.to_s.split("/", 2)
        @track_number = track[0].to_i32
        if track.size > 1
          @track_total = track[1].to_i32
        end
      when "tracktotal", "totaltracks"
        @track_total = value.to_i
      when "discnumber", "disknumber"
        disc = value.to_s.split("/", 2)
        @disc_number = disc[0].to_i32
        if disc.size > 1
          @disc_total = disc[1].to_i32
        end
      when "disktotal", "disctotal", "totaldisks", "totaldiscs"
        @disc_total = value.to_i32
      else
        @custom[var_name.upcase] = value.to_s
      end
    end

    def add_picture(pic : FLACPicture) : Nil
      @pictures.push(pic)
    end

    def clear_pictures : Nil
      @pictures = Array(FLACPicture).new
    end
    
  end
end