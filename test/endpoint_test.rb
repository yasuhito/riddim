# frozen_string_literal: true

require 'fileutils'
require 'minitest/autorun'
require 'tmpdir'
require_relative '../lib/riddim/ownership'

# Sets RIDDIM_STATE_DIR to a fresh directory with one published record for
# the duration of one test; a nil value removes it.
module EndpointStateEnv
  ENDPOINT_FIELDS = {
    'window' => 'lab:w9:p2',
    'endpoint_task_id' => 'worker',
    'harness' => 'pi',
    'model' => 'openrouter/z-ai/glm-5.3-flash',
    'effort' => 'max',
    'spawn_gen' => 's1767200000.4242.7',
    'backend' => 'herdr',
    'herdr_session' => 'lab',
    'herdr_workspace_id' => 'w9',
    'herdr_tab_id' => 'w9:t1',
    'herdr_pane_id' => 'w9:p2'
  }.freeze

  def with_started_record(overrides = {})
    Dir.mktmpdir do |dir|
      state = File.join(dir, 'state')
      Dir.mkdir(state)
      path = File.join(state, 'worker.meta')
      File.write(path, Riddim::Ownership.serialize(ENDPOINT_FIELDS.merge(overrides)))

      with_state_dir(state) { yield path }
    end
  end

  private

  def with_state_dir(value)
    original = ENV.fetch('RIDDIM_STATE_DIR', nil)
    ENV['RIDDIM_STATE_DIR'] = value
    yield
  ensure
    ENV['RIDDIM_STATE_DIR'] = original
  end
end

class OwnershipEndpointResolutionTest < Minitest::Test
  include EndpointStateEnv

  def test_resolves_the_exact_recorded_endpoint
    with_started_record do
      resolved = Riddim::Ownership::Endpoint.resolve('worker')

      assert_equal Riddim::Ownership::Endpoint::Resolved.new('lab', 'w9', 'w9:t1', 'w9:p2'), resolved
    end
  end
end

class OwnershipEndpointRefusalTest < Minitest::Test
  include EndpointStateEnv

  def test_refuses_a_missing_record
    Dir.mktmpdir do |dir|
      state = File.join(dir, 'state')
      Dir.mkdir(state)

      with_state_dir(state) do
        assert_raises(Riddim::Ownership::Endpoint::Refused) { Riddim::Ownership::Endpoint.resolve('worker') }
      end
    end
  end

  def test_refuses_a_symlinked_record_without_following_the_link
    with_started_record do |path|
      target = File.join(File.dirname(path), 'elsewhere.meta')
      FileUtils.mv(path, target)
      File.symlink(target, path)

      assert_raises(Riddim::Ownership::Endpoint::Refused) { Riddim::Ownership::Endpoint.resolve('worker') }
    end
  end

  def test_refuses_a_record_that_is_not_a_regular_file
    with_started_record do |path|
      File.delete(path)
      Dir.mkdir(path)

      assert_raises(Riddim::Ownership::Endpoint::Refused) { Riddim::Ownership::Endpoint.resolve('worker') }
    end
  end

  def test_refuses_a_malformed_record
    with_started_record do |path|
      File.write(path, "spawn_gen=s1\nnot a record\n")

      assert_raises(Riddim::Ownership::Endpoint::Refused) { Riddim::Ownership::Endpoint.resolve('worker') }
    end
  end

  def test_refuses_a_record_with_a_duplicated_field
    with_started_record do |path|
      bytes = File.read(path)
      File.write(path, bytes.sub("endpoint_task_id=worker\n", "endpoint_task_id=worker\nendpoint_task_id=worker\n"))

      assert_raises(Riddim::Ownership::Endpoint::Refused) { Riddim::Ownership::Endpoint.resolve('worker') }
    end
  end

  def test_refuses_a_record_bound_to_another_name
    with_started_record('endpoint_task_id' => 'other') do
      assert_raises(Riddim::Ownership::Endpoint::Refused) { Riddim::Ownership::Endpoint.resolve('worker') }
    end
  end

  def test_refuses_a_record_on_another_harness
    with_started_record('harness' => 'codex') do
      assert_raises(Riddim::Ownership::Endpoint::Refused) { Riddim::Ownership::Endpoint.resolve('worker') }
    end
  end

  def test_refuses_a_record_on_another_backend
    with_started_record('backend' => 'tmux') do
      assert_raises(Riddim::Ownership::Endpoint::Refused) { Riddim::Ownership::Endpoint.resolve('worker') }
    end
  end

  def test_refuses_malformed_herdr_endpoint_atoms
    with_started_record('herdr_session' => 'bad session', 'window' => 'bad session:w9:p2') do
      assert_raises(Riddim::Ownership::Endpoint::Refused) { Riddim::Ownership::Endpoint.resolve('worker') }
    end
  end

  def test_refuses_a_window_inconsistent_with_the_recorded_session_and_pane
    with_started_record('window' => 'lab:w9:p1') do
      assert_raises(Riddim::Ownership::Endpoint::Refused) { Riddim::Ownership::Endpoint.resolve('worker') }
    end
  end
end

class OwnershipEndpointPublicationTest < Minitest::Test
  Profile = Struct.new(:harness, :model, :effort)
  Workspace = Struct.new(:workspace_id, :tab_id, :root_pane_id)

  def test_refuses_to_publish_malformed_herdr_endpoint_atoms
    profile = Profile.new('pi', 'model', 'max')
    workspace = Workspace.new('bad/workspace', 'w9:t1', 'w9:p1')

    assert_raises(Riddim::Ownership::InvalidValue) do
      Riddim::Ownership::Endpoint.fields(
        name: 'worker', profile: profile, spawn_gen: 's1.2.3', session: 'lab', workspace: workspace
      )
    end
  end
end
