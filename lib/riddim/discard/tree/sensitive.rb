# frozen_string_literal: true

module Riddim
  module Discard
    # Existing tracked fixtures are not new secret data. Exempt only unchanged
    # paths with byte-identical HEAD contents, never just Git's cached status.
    module Tree
      module_function

      def verify_sensitive!(directory, path, state, content)
        return unless path.split('/').any? { |part| sensitive?(part) }
        return if state == '  ' && matches_head?(directory, path, content)

        raise Refused, 'dirty or untracked sensitive paths are not discardable; retaining assets'
      end

      def matches_head?(directory, path, content)
        return false unless content

        directory_entry = content.fetch(:type) == 'directory'
        bytes, result = Result.git(directory, 'cat-file', directory_entry ? '-t' : 'blob', "HEAD:#{path}")
        return false unless result.success?
        return bytes.strip == 'tree' if directory_entry

        Digest::SHA256.hexdigest(bytes) == content.fetch(:sha256)
      end

      def sensitive?(part)
        part.match?(/\A(?:\.env.*|\.ssh|\.aws|\.(?:netrc|npmrc|pypirc)|\.?(?:credentials|secrets?)(?:\..*)?)\z/i) ||
          part.match?(/\A(?:id_(?:rsa|dsa|ecdsa|ed25519)|auth\.json)\z/i) ||
          part.match?(/\.(?:pem|key|p12|pfx|keystore)\z/i)
      end
    end
  end
end
