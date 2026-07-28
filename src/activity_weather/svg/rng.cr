module ActivityWeather
  module SVG
    # Deterministic pseudo-randomness for scattered scenery — star fields,
    # hill ridgelines, precipitation offsets. Seeded from the repository name
    # so every repo gets its own sky, while the same repo always renders the
    # same bytes: golden files stay stable and READMEs do not churn on every
    # scheduled run. Never use the stdlib Random here for exactly that reason.
    class Rng
      def initialize(seed : String)
        @state = fnv1a(seed)
        # A zero state would emit a constant stream.
        @state = 0x9747b28c_u32 if @state.zero?
      end

      # In [0, 1).
      def next_float : Float64
        @state = (@state &* 1664525_u32) &+ 1013904223_u32
        (@state >> 8).to_f64 / (1_u32 << 24).to_f64
      end

      def between(min : Float64, max : Float64) : Float64
        min + next_float * (max - min)
      end

      private def fnv1a(text : String) : UInt32
        hash = 0x811c9dc5_u32
        text.each_byte do |byte|
          hash = (hash ^ byte) &* 0x01000193_u32
        end
        hash
      end
    end
  end
end
