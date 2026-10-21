# frozen_string_literal: true

require_relative 'ownership'

module Riddim
  # Records Pi's exact-project trust decision before a worktree can launch.
  module PiTrust
    CONFIG_RESOURCES = %w[
      settings.json mcp.json extensions skills prompts themes SYSTEM.md APPEND_SYSTEM.md
    ].freeze

    class Error < Ownership::Error; end

    module_function

    def ensure_worktree_trusted!(worktree)
      path = File.realpath(worktree)
      return unless trust_required?(path)

      Store.record_true!(agent_directory(path), path)
    rescue Error
      raise
    rescue SystemCallError, ArgumentError => e
      raise Error, "Pi trust store cannot be updated safely: #{e.message}"
    end

    def trust_required?(worktree)
      project_config_resources?(worktree) || ancestor_agent_skills?(worktree)
    end

    def project_config_resources?(worktree)
      config = File.join(worktree, '.pi')
      CONFIG_RESOURCES.any? { |name| File.exist?(File.join(config, name)) }
    end

    def ancestor_agent_skills?(worktree)
      home_skills = File.join(canonical_path(Dir.home), '.agents', 'skills')
      current = canonical_path(worktree)
      loop do
        skills = File.join(current, '.agents', 'skills')
        return true if skills != home_skills && File.exist?(skills)

        parent = File.dirname(current)
        return false if parent == current

        current = parent
      end
    end

    def canonical_path(path)
      File.realpath(path)
    rescue SystemCallError
      path
    end

    def agent_directory(worktree)
      configured = ENV.fetch('PI_CODING_AGENT_DIR', nil)
      return File.join(Dir.home, '.pi', 'agent') if configured.nil? || configured.empty?

      File.expand_path(expand_agent_directory(configured), worktree)
    end

    def expand_agent_directory(path)
      raise Error, 'PI_CODING_AGENT_DIR file URLs are unsupported for safe trust updates' if path.start_with?('file://')
      return Dir.home if path == '~'
      return File.join(Dir.home, path.delete_prefix('~/')) if path.start_with?('~/')

      path
    end
  end
end

require_relative 'pi_trust/store'
