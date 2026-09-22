# frozen_string_literal: true

module Riddim
  module Ownership
    # Read-only resolution of one endpoint ownership record to the exact
    # Herdr endpoint it binds. The record at state/<name>.meta is the
    # ownership authority: a command may act on an endpoint only while its
    # own record still binds that endpoint to the requested name, so every
    # refusal happens here, before any Herdr command is constructed. The
    # record is read the way Ownership removes one - opened with O_NOFOLLOW,
    # required to be a regular file - and parsed against the exact published
    # ownership fields, so a missing, symlinked, unreadable, malformed,
    # duplicated, or inconsistent record is refused. Additional well-formed
    # metadata is preserved without becoming routing authority. Nothing is inferred
    # from labels: only the record's own endpoint_task_id, harness, backend,
    # window, and herdr_ fields decide.
    module Endpoint
      # Firstmate's endpoint atom: Herdr session/workspace ids use it as-is;
      # tab and pane ids use the same shape after their structural colons are
      # normalized to underscores.
      ATOM_PATTERN = /\A[A-Za-z0-9._@%+-]+\z/

      # The exact Herdr endpoint identities one ownership record binds,
      # exactly as Herdr reported them when the endpoint was created.
      Resolved = Struct.new(:session, :workspace_id, :tab_id, :pane_id)

      # One refused resolution. The command surfaces it as Riddim's own
      # failure instead of touching Herdr.
      class Refused < Error; end

      module_function

      # Builds the exact Firstmate fields Riddim publishes, refusing response
      # ids that a later metadata-routed operation could not safely accept.
      def fields(name:, profile:, spawn_gen:, session:, workspace:)
        validate_atoms!(session, workspace.workspace_id, workspace.tab_id, workspace.root_pane_id)
        pane = workspace.root_pane_id
        { 'window' => "#{session}:#{pane}", 'endpoint_task_id' => name, 'harness' => profile.harness,
          'model' => profile.model, 'effort' => profile.effort, 'spawn_gen' => spawn_gen, 'backend' => 'herdr',
          'herdr_session' => session, 'herdr_workspace_id' => workspace.workspace_id,
          'herdr_tab_id' => workspace.tab_id, 'herdr_pane_id' => pane }
      end

      # Resolves the ownership record of <name> into the exact Herdr endpoint
      # identities it binds.
      def resolve(name)
        resolve_snapshot(name).first
      end

      # Capture the endpoint and its incarnation together, so an observer can
      # discard backend evidence if ownership changes during its read.
      def resolve_snapshot(name)
        path = Ownership.record_path(name)
        fields = parse_record(name, path)
        validate(name, path, fields)
        endpoint = Resolved.new(
          fields.fetch('herdr_session'), fields.fetch('herdr_workspace_id'),
          fields.fetch('herdr_tab_id'), fields.fetch('herdr_pane_id')
        ).freeze
        [endpoint, fields.fetch('spawn_gen')].freeze
      end

      def unchanged?(name, snapshot)
        resolve_snapshot(name) == snapshot
      rescue Refused
        false
      end

      # Parses the record bytes at <path> with the exact published schema. A
      # record that is unreadable, truncated, or duplicated never reads back
      # as ownership evidence; unrelated metadata may be added safely.
      def parse_record(name, path)
        Ownership.parse(read_bytes(path))
      rescue Ownership::InvalidRecord => e
        raise Refused, "the endpoint record for #{name} at #{path} is unreadable: #{e.message}"
      end

      # The complete bytes of one record. The path is opened with O_NOFOLLOW,
      # so a symlinked record refuses instead of being followed, and the
      # descriptor must be a regular file, so a directory or device at the
      # record path refuses instead of being read.
      def read_bytes(path)
        File.open(path, File::RDONLY | File::NOFOLLOW) do |file|
          raise Refused, "the endpoint record at #{path} is not a regular file" unless file.stat.file?

          file.read
        end
      rescue Errno::ENOENT
        raise Refused, "no endpoint record exists at #{path}"
      rescue Errno::ELOOP
        raise Refused, "the endpoint record at #{path} is a symbolic link"
      rescue SystemCallError => e
        raise Refused, "the endpoint record at #{path} could not be read: #{e.message}"
      end

      # Binds the record to the requested name and to Riddim's own endpoint
      # shape: the record must still name the requested task, the Pi harness
      # on the Herdr backend, and a window that is exactly the recorded
      # session and pane. A record that disagrees with itself or with the
      # request is refused, never repaired or reinterpreted.
      def validate(name, path, fields)
        refuse_unbound_name(name, path, fields)
        refuse_wrong_harness(name, fields)
        refuse_wrong_backend(name, fields)
        refuse_malformed_atoms(name, fields)
        refuse_inconsistent_window(name, fields)
      end

      def validate_atoms!(session, workspace, tab, pane)
        return if valid_atoms?(session, workspace, tab, pane)

        raise InvalidValue, 'Herdr endpoint ids contain characters outside Firstmate endpoint atoms'
      end

      def valid_atoms?(session, workspace, tab, pane)
        endpoint_atom?(session) && endpoint_atom?(workspace) &&
          endpoint_atom?(tab.tr(':', '_')) && endpoint_atom?(pane.tr(':', '_'))
      end

      def endpoint_atom?(value)
        value.is_a?(String) && value.match?(ATOM_PATTERN)
      end

      # The record must still name the requested task: a record published for
      # another name is refused, never borrowed.
      def refuse_unbound_name(name, path, fields)
        task_id = fields.fetch('endpoint_task_id')
        return if task_id == name

        raise Refused, "the endpoint record at #{path} belongs to #{task_id.dump}, not #{name.dump}"
      end

      # Riddim's endpoint shape is Pi on Herdr only: any other harness is
      # refused, never adapted.
      def refuse_wrong_harness(name, fields)
        harness = fields.fetch('harness')
        return if harness == 'pi'

        raise Refused, "the endpoint record for #{name} records harness #{harness.dump}, not \"pi\""
      end

      # Riddim's endpoint shape is Pi on Herdr only: any other backend is
      # refused, never adapted.
      def refuse_wrong_backend(name, fields)
        backend = fields.fetch('backend')
        return if backend == 'herdr'

        raise Refused, "the endpoint record for #{name} records backend #{backend.dump}, not \"herdr\""
      end

      # Every recorded Herdr identity must have Firstmate's endpoint-atom
      # shape before any value can become a subprocess argument.
      def refuse_malformed_atoms(name, fields)
        values = fields.values_at('herdr_session', 'herdr_workspace_id', 'herdr_tab_id', 'herdr_pane_id')
        return if valid_atoms?(*values)

        raise Refused, "the endpoint record for #{name} contains malformed Herdr endpoint ids"
      end

      # The window must be exactly the recorded session and pane: a window
      # that disagrees with the record's own herdr_ fields is refused, never
      # resolved from either half.
      def refuse_inconsistent_window(name, fields)
        window = fields.fetch('window')
        expected = "#{fields.fetch('herdr_session')}:#{fields.fetch('herdr_pane_id')}"
        return if window == expected

        raise Refused, "the endpoint record for #{name} records window #{window.dump}, not #{expected.dump}"
      end
    end
  end
end
