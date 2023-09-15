# flactag.cr
FLAC tag library written in Crystal.

## Installation
Add this to your application's shard.yml:
```yaml
dependencies:
  flactag:
    github: Sorrow446/flactag.cr
```

## Usage
```crystal
require "flactag"
```
Opening and exception handling are omitted from the examples.
```crystal
FLACTag.open("1.flac") do |flac|
  # Stuff.
end
```

Read album title:
```crystal
tags = flac.read
puts(tags.album)
```

Extract all pictures:
```crystal
tags = flac.read
tags.pictures.each_with_index(1) do |p, idx|
  File.write(idx.to_s + ".jpg", p.data)
end
```

Write album title and year:
```crystal
tags = FLACTag::FLACTags.new
tags.title = "my title"
tags.year = 2023
flac.write(tags)
```

You can also set tags via its update function instead of dot notation (underscores are removed). 
```crystal
tags = FLACTag::FLACTags.new
tags.update("track_number", 10)
tags.update("mycustomtag", "val")
```

Write two covers, retaining any already written:
```crystal
def read_pic_data(pic_path : String) : Bytes
  File.open(pic_path, "rb") do |f|
    f.getb_to_end
  end
end

tags = FLACTag::FLACTags.new

pic_data = read_pic_data("1.jpg")
pic = FLACTag::FLACCover.new
pic.height = 1200
pic.width = 1200
pic.description = "my desc"
pic.mime_type = "image/jpeg"

pic_two_data = read_pic_data("2.jpg")
pic_two = FLACTag::FLACCover.new
pic_two.height = 1000
pic_two.width = 1000
pic_two.mime_type = "image/jpeg"
pic_two.type = FLACTag::PictureType::BackCover

# Or tags.pictures.push(pic).
tags.add_picture(pic)
tags.add_picture(pic_two)
flac.write(tags)
```

Delete all tags and the second picture:
```crystal
tags = FLACTag::FLACTags.new
flac.write(tags, ["all_tags", "picture:2"])
```

Read bit-depth and sample rate:
```crystal
si = flac.read_stream_info
puts("#{si.bit_depth}-bit / #{si.sample_rate} Hz")
```

## Deletion strings
```
album
album_artist
all_pictures
all_custom
all_tags
artist
comment
compilation
date
disc_number
disc_total
encoder
genre
isrc
itunes_advisory
length
lyrics
performer
picture:(index starting from 1)
publisher
title
track_number
track_total
upc
vendor
year
```
Case-insensitive. Any others will be assumed to be custom tags.

## Objects
```crystal
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
```

## Thank you
- flactag.cr's bit reader was ported from mewkiz's Go FLAC library.
- Crystal Discord community for their assistance with any language problems.
