# frozen_string_literal: true

module Riddim
  # Keep the task's private brief under a generation-specific archival name.
  module Teardown
    module_function

    def brief_paths!(task)
      brief = TaskBrief.path(task.name)
      archived = File.join(File.expand_path(Ownership.state_dir), "#{task.name}.#{task.generation}.brief")
      verify_private_brief!(brief)
      raise Refused, 'archived brief already exists; retaining assets' if Ownership.record_present?(archived)

      [brief, archived]
    end

    def verify_private_brief!(brief)
      File.open(brief, File::RDONLY | File::NOFOLLOW) do |file|
        stat = file.stat
        raise Refused, 'worker brief is not private and regular; retaining assets' unless
          stat.file? && stat.uid == Process.euid && stat.mode.nobits?(0o077)
      end
    end

    def archive_brief!(brief, archived)
      raise Refused, 'archived brief appeared; retaining record' if Ownership.record_present?(archived)

      File.rename(brief, archived)
    end
  end
end
