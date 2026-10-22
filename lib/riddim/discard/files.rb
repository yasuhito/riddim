# frozen_string_literal: true

module Riddim
  # Scrub only the approved files before ordinary non-forced worktree removal.
  module Discard
    module_function

    def discard_files!(task, scope, audit)
      return unless scope.fetch(:files).any? { |file| file.fetch(:status) != '  ' }

      note!(audit, 'files-discarding') # Persist evidence before the first irreversible file mutation.
      unlink_untracked!(task, scope)
      Teardown.git!(task.worktree, 'restore', '--source', scope.fetch(:head), '--staged', '--worktree', '--', '.')
      note!(audit, 'files-discarded')
      verify_discarded_files!(task, scope)
    end

    def unlink_untracked!(task, scope)
      scope.fetch(:files).each do |file|
        next unless file.fetch(:status) == '??'

        File.unlink(File.join(task.worktree, file.fetch(:path)))
      end
    end

    def verify_discarded_files!(task, scope)
      Teardown.verify_owner!(task)
      _, head = Result.verified_tips(task.name, task.fields)
      tree = Tree.inspect!(task.worktree)
      return if head == scope.fetch(:head) && tree.fetch(:files).all? { |file| file.fetch(:status) == '  ' }

      raise Refused, 'source changed during file discard; retaining remaining assets'
    end
  end
end
