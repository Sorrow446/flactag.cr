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
  # stuff
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
flac.write(tags, [] of String)
```

Write two covers, retaining any already written:
```crystal
def read_pic_data(pic_path : String) : Bytes
  data = Bytes.new(0)
  File.open(pic_path, "rb") do |f|
    data = f.getb_to_end
  end
  return data
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

# or tags.pictures.push(pic)
tags.add_picture(pic)
tags.add_picture(pic_two)
flac.write(tags, [] of String)
```

Delete all tags and the second picture:
```crystal
tags = FLACTag::FLACTags.new
flac.write(tags, ["all_tags", "picture:2"]
```
