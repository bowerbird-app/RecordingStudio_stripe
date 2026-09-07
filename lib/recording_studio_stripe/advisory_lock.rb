# frozen_string_literal: true

require "zlib"

module RecordingStudioStripe
  module AdvisoryLock
    module_function

    def hold(connection, name)
      return unless connection.adapter_name.match?(/postg/i)

      connection.execute("SELECT pg_advisory_xact_lock(#{Zlib.crc32(name.to_s)})")
    end
  end
end
