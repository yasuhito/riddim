# frozen_string_literal: true

require 'open3'

module Riddim
  # Paths inherited by a Riddim CLI invoked from its own linked Git worktree.
  # The marker lives in that worktree's Git admin directory, outside the files
  # the worker edits or commits. Explicit environment overrides still win.
  module RuntimePaths
    ROOT = File.expand_path('../..', __dir__)
    FIELDS = %w[project worktree config_dir state_dir].freeze
    GIT_ENV = { 'GIT_DIR' => nil, 'GIT_WORK_TREE' => nil, 'GIT_COMMON_DIR' => nil,
                'GIT_INDEX_FILE' => nil }.freeze

    class Error < StandardError; end

    module_function

    def activate!
      fields = read_for_source
      return unless fields

      %w[config_dir state_dir].each do |field|
        variable = "RIDDIM_#{field.upcase}"
        ENV[variable] = fields.fetch(field) if ENV[variable].nil? || ENV[variable].empty?
      end
    end

    def read_for_source
      git_entry = File.join(ROOT, '.git')
      return unless File.exist?(git_entry) || File.symlink?(git_entry)

      source_marker
    rescue Errno::ENOENT => e
      raise Error, "linked worktree paths are unavailable: #{e.message}" if File.file?(git_entry)

      nil # The original checkout can run without Git installed.
    end

    def source_marker
      root = File.realpath(ROOT)
      git_dir = git_path(root, '--absolute-git-dir')
      common = git_path(root, '--path-format=absolute', '--git-common-dir')
      return if git_dir == common

      marker = File.join(git_dir, 'riddim-home')
      return unless File.exist?(marker) || File.symlink?(marker)

      fields = read_marker(marker)
      verify_marker!(fields, root, common, marker)
      fields
    end

    def verify_marker!(fields, root, common, marker)
      raise Error, "worktree path disagrees with #{marker}" unless fields.fetch('worktree') == root
      return if git_path(fields.fetch('project'), '--path-format=absolute', '--git-common-dir') == common

      raise Error, "project repository disagrees with #{marker}"
    end

    def git_path(root, *flags)
      stdout, _stderr, status = Open3.capture3(GIT_ENV, 'git', '-C', root, 'rev-parse', *flags)
      raise Error, "cannot locate Riddim's linked Git worktree at #{root}" unless status.success?

      File.realpath(stdout.strip)
    end

    def read_marker(path)
      File.open(path, File::RDONLY | File::NOFOLLOW) do |file|
        raise Error, "worktree marker is not a regular file: #{path}" unless file.stat.file?

        parse(file.read, path)
      end
    rescue SystemCallError => e
      raise Error, "worktree marker cannot be read at #{path}: #{e.message}"
    end

    def parse(bytes, path)
      text = bytes.dup.force_encoding(Encoding::UTF_8)
      raise Error, "invalid worktree marker at #{path}" unless text.valid_encoding? && text.end_with?("\n")

      pairs = text.lines.map { |line| line.delete_suffix("\n").partition('=').values_at(0, 2) }
      validate_pairs!(pairs, path)
      pairs.to_h
    end

    def validate_pairs!(pairs, path)
      raise Error, "invalid worktree marker at #{path}" unless pairs.map(&:first).sort == FIELDS.sort
      return if pairs.all? { |_, value| valid_path?(value) }

      raise Error, "invalid worktree paths at #{path}"
    end

    def valid_path?(value)
      value.start_with?('/') && !value.match?(/[[:cntrl:]]/)
    end

    def serialize(fields)
      "#{FIELDS.map { |key| "#{key}=#{fields.fetch(key)}" }.join("\n")}\n"
    end
  end
end
