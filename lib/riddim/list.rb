# frozen_string_literal: true

require_relative 'ownership'

module Riddim
  # A read-only ownership inventory. A row reports a recorded endpoint, not a
  # live agent. No Herdr labels or process status are used as ownership evidence.
  module List
    module_function

    def rows
      record_names.filter_map do |name|
        endpoint = Ownership::Endpoint.resolve(name)
        [name, endpoint.session, endpoint.pane_id]
      rescue Ownership::Endpoint::Refused
        # Like Firstmate's snapshot, a record removed during enumeration is
        # absent. Any still-present but invalid record fails the whole read.
        raise if Ownership.record_present?(Ownership.record_path(name))
      end
    end

    def record_names
      dir = Ownership.state_dir
      begin
        info = File.lstat(dir)
      rescue Errno::ENOENT
        return []
      end
      raise Ownership::Error, "the state directory is not a real directory: #{dir}" unless info.directory?

      Dir.children(dir).filter_map { |entry| record_name(entry) }.sort
    end

    def record_name(entry)
      return unless entry.b.end_with?('.meta')

      raise Ownership::Error, "invalid endpoint record filename: #{entry.dump}" unless entry.valid_encoding?

      Ownership.validated_name(entry.delete_suffix('.meta'))
    end
  end
end
