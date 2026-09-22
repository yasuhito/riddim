# frozen_string_literal: true

require_relative 'herdr'
require_relative 'ownership'

module Riddim
  # The start command's orchestration: Firstmate's spawn sequence, reduced to
  # what Riddim owns. One per-name record lock is held from duplicate
  # preflight through launch result; any existing record, including a
  # malformed one, refuses the start before Herdr is invoked at all. Then, in
  # Firstmate's order, the exact endpoint is created, the authoritative
  # ownership record is published, and the agent starts. The Herdr surface
  # performs no rollback of its own: every cleanup decision lives here, next
  # to the record whose retention rules it must respect.
  module Start
    module_function

    # Runs one complete locked start, exiting the process on every failure
    # with the exit status Herdr's own output and status deserve.
    def run(name, profile)
      Ownership.ensure_state_dir
      record_path = Ownership.record_path(name)
      Ownership.with_lock(name) { start_locked(name, profile, record_path) }
    rescue Ownership::Error, SystemCallError => e
      exit_on_error(e)
    end

    def start_locked(name, profile, record_path)
      refuse_duplicate(name, record_path)
      workspace = create_endpoint(name)
      spawn_gen = publish_record(name, profile, record_path, workspace)
      launch(name, profile, record_path, workspace, spawn_gen)
    end

    def exit_on_error(error)
      warn "riddim: #{error.message}"
      exit 1
    end

    # Any existing record, even a malformed one, refuses the start before any
    # Herdr mutation, like Firstmate's duplicate-launch corridor.
    def refuse_duplicate(name, record_path)
      return unless Ownership.record_present?(record_path)

      warn "riddim: refusing to start #{name}: an endpoint record already exists at #{record_path}"
      exit 1
    end

    # The exact endpoint of this start: one unfocused workspace, one root pane.
    def create_endpoint(name)
      Riddim::Herdr.create_workspace(cwd: Dir.pwd, label: "riddim-#{name}")
    rescue Riddim::Herdr::CommandFailed => e
      $stdout.write(e.stdout)
      $stderr.write(e.stderr)
      exit e.exitstatus
    rescue Riddim::Herdr::InvalidResponse => e
      warn "riddim: invalid Herdr workspace JSON: #{e.message}"
      exit 1
    end

    # Publishes the ownership record and returns the fresh spawn generation it
    # carries. The record is the ownership authority: exact response-derived
    # Herdr identities, published atomically after the endpoint exists and
    # never over an existing record. A value that cannot render as one
    # nonempty line is a publication failure like any other.
    def publish_record(name, profile, record_path, workspace)
      spawn_gen = Ownership.fresh_spawn_gen
      fields = Ownership::Endpoint.fields(
        name: name, profile: profile, spawn_gen: spawn_gen, session: Riddim::Herdr.session, workspace: workspace
      )
      Ownership.publish(record_path, Ownership.serialize(fields))
      spawn_gen
    rescue Ownership::Error => e
      rollback_after_failed_publication(workspace, e)
    end

    # Publication failed after the endpoint exists: attempt the same
    # confirmed exact-pane rollback a failed start gets. No record of this
    # start was published, so there is none to remove - and a record another
    # writer just claimed is left untouched. The exact endpoint identities
    # are reported either way; cleanup is claimed only when the pane get
    # confirmed the pane gone.
    def rollback_after_failed_publication(workspace, error)
      confirmed = Riddim::Herdr.close_pane_confirmed(workspace.root_pane_id)
      warn "riddim: #{error.message}"
      if confirmed
        warn "riddim: cleanup confirmed: #{endpoint(workspace)} was closed and confirmed gone"
      else
        warn "riddim: cleanup unconfirmed: #{endpoint(workspace)} may still exist"
      end
      exit 1
    end

    def launch(name, profile, record_path, workspace, spawn_gen)
      Riddim::Herdr.start_agent(
        name: name, pane_id: workspace.root_pane_id, model: profile.model, effort: profile.effort
      )
      puts "started #{name} in #{workspace.root_pane_id}"
    rescue Riddim::Herdr::CommandFailed, SystemCallError => e
      cleanup_failed_start(name, record_path, workspace, spawn_gen, e)
    end

    # One exact pane close, then a pane get: only Herdr's structured
    # pane_not_found response confirms the pane gone. The record is removed
    # only after that confirmation and only while it still carries this
    # start's spawn generation; otherwise it is retained and reported,
    # without masking Herdr's own failure. The cleanup is pane-scoped: a
    # workspace is never closed.
    def cleanup_failed_start(name, record_path, workspace, spawn_gen, failure)
      confirmed = Riddim::Herdr.close_pane_confirmed(workspace.root_pane_id)
      report_failed_start(failure)
      unless confirmed && Ownership.remove_if_unchanged_under_lock(record_path, spawn_gen)
        report_retained_record(name, record_path, workspace, confirmed)
      end
      exit exit_status_of(failure)
    end

    # Herdr's own failure output passes through unchanged; a Herdr executable
    # that cannot be launched at all reports Riddim's own error instead.
    def report_failed_start(failure)
      if failure.is_a?(Riddim::Herdr::CommandFailed)
        $stdout.write(failure.stdout)
        $stderr.write(failure.stderr)
      else
        warn "riddim: #{failure.message}"
      end
    end

    def exit_status_of(failure)
      failure.is_a?(Riddim::Herdr::CommandFailed) ? failure.exitstatus : 1
    end

    def report_retained_record(name, record_path, workspace, confirmed)
      reason =
        if confirmed
          'the created pane was closed and confirmed gone, ' \
            "but the record could not be verified as this start's own (#{endpoint(workspace)})"
        else
          "the created pane was not confirmed closed (#{endpoint(workspace)}); it may still exist"
        end
      warn "riddim: the endpoint record for #{name} is retained at #{record_path}: #{reason}"
    end

    # The exact identities of one created endpoint, as Herdr reported them.
    def endpoint(workspace)
      "session #{Riddim::Herdr.session} workspace #{workspace.workspace_id} " \
        "tab #{workspace.tab_id} pane #{workspace.root_pane_id}"
    end
  end
end
