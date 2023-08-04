require "./flactag/*"

module FLACTag
  def self.open(flac_path : String) : Nil
    f = FLACTag::FLAC.new(flac_path)
    yield f ensure f.close
  end
end