# frozen_string_literal: true

module SaytimeWeather
  module SoundIndex
    def sound_index_for(sound_dir)
      @sound_indexes ||= {}
      @sound_indexes[sound_dir] ||= build_sound_index(sound_dir)
    end

    def build_sound_index(sound_dir)
      index = { 'paths' => {}, 'abs_set' => {}, 'wx_names' => [] }
      return index unless Dir.exist?(sound_dir)

      Dir.glob(File.join(sound_dir, '**', '*.ulaw')).each do |abs|
        rel = abs.sub("#{sound_dir}/", '')
        index['paths'][rel] = abs
        base = File.basename(abs)
        index['paths'][base] = abs unless index['paths'].key?(base)
        index['abs_set'][abs] = true
      end

      wx_dir = File.join(sound_dir, 'wx')
      if Dir.exist?(wx_dir)
        index['wx_names'] = Dir.glob(File.join(wx_dir, '*.ulaw')).map do |f|
          File.basename(f, '.ulaw').downcase
        end
      end

      index
    end

    def resolve_sound_path(sound_dir, relative)
      idx = sound_index_for(sound_dir)
      idx['paths'][relative] || idx['paths'][File.basename(relative)] || File.join(sound_dir, relative)
    end
  end
end
