# frozen_string_literal: true

module Riddim
  # The local launch policy: exact provider/model IDs Riddim may start.
  # One literal ID per line; membership is byte-exact, with no globs, aliases
  # or provider fallback. A missing, unreadable, malformed or empty list
  # refuses every launch. This gates Riddim's own launches only: it is an
  # editable local file, not a sandbox or a billing cap.
  module ModelAllowlist
    FILENAME = 'allowed-models'
    ENTRY = %r{\A[^/]+/.+\z}
    MALFORMED_ENTRY = 'expected one provider/model ID without spaces or control characters'
    SETUP_HINT = "list one approved provider/model ID per line (see config/#{FILENAME}.example)".freeze

    class Error < StandardError; end

    module_function

    # The model is compared as UTF-8 bytes, whatever the caller's argv locale.
    def verify!(model, config_dir:)
      path = File.join(config_dir, FILENAME)
      model = model.dup.force_encoding(Encoding::UTF_8)
      return if load(path).include?(model)

      raise Error, "model #{model.dump} is not allowed: #{identity(model)} not listed in #{path}; " \
                   'add its exact provider/model ID only if a human approved it'
    end

    def load(path)
      begin
        text = File.binread(path)
      rescue Errno::ENOENT
        raise Error, "missing model allowlist #{path}: #{SETUP_HINT}"
      rescue SystemCallError => e
        raise Error, "unreadable model allowlist #{path}: #{e.message}"
      end

      entries = parse(text, path)
      raise Error, "empty model allowlist #{path}: #{SETUP_HINT}" if entries.empty?

      entries
    end

    def parse(text, path)
      text = text.force_encoding(Encoding::UTF_8)
      raise Error, "malformed model allowlist #{path}: valid UTF-8 is required" unless text.valid_encoding?

      text.lines.each_with_index.filter_map do |line, index|
        entry = line.strip
        next if entry.empty? || entry.start_with?('#')

        next entry if valid_entry?(entry)

        raise Error, "malformed model allowlist #{path} line #{index + 1}: #{MALFORMED_ENTRY}"
      end
    end

    def valid_entry?(entry)
      entry.match?(ENTRY) && !entry.match?(/[\p{Cc}\p{Cf}\p{Z}]/)
    end

    def identity(model)
      provider, separator, id = model.partition('/')
      return 'it names no provider and is' if separator.empty?

      "provider #{provider.dump} model #{id.dump} is"
    end

    private_class_method :load, :parse, :valid_entry?, :identity
  end
end
