# frozen_string_literal: true

require 'fileutils'
require 'minitest/autorun'
require 'tmpdir'
require_relative '../lib/riddim/ownership'

# Sets RIDDIM_STATE_DIR for the duration of one test; a nil value removes it.
module StateDirEnv
  def with_state_dir(value)
    original = ENV.fetch('RIDDIM_STATE_DIR', nil)
    ENV['RIDDIM_STATE_DIR'] = value
    yield
  ensure
    ENV['RIDDIM_STATE_DIR'] = original
  end
end

# Sets the process umask for the duration of one test.
module UmaskEnv
  def with_umask(mask)
    original = File.umask(mask)
    yield
  ensure
    File.umask(original)
  end
end

# The exact published bytes of one endpoint ownership record, in Firstmate's
# field order.
OWNERSHIP_BYTES = <<~RECORD
  window=default:w9:p1
  endpoint_task_id=worker
  harness=pi
  model=openrouter/z-ai/glm-5.3-flash
  effort=max
  spawn_gen=s1767200000.4242.7
  backend=herdr
  herdr_session=default
  herdr_workspace_id=w9
  herdr_tab_id=w9:t1
  herdr_pane_id=w9:p1
RECORD

OWNERSHIP_FIELDS = {
  'window' => 'default:w9:p1',
  'endpoint_task_id' => 'worker',
  'harness' => 'pi',
  'model' => 'openrouter/z-ai/glm-5.3-flash',
  'effort' => 'max',
  'spawn_gen' => 's1767200000.4242.7',
  'backend' => 'herdr',
  'herdr_session' => 'default',
  'herdr_workspace_id' => 'w9',
  'herdr_tab_id' => 'w9:t1',
  'herdr_pane_id' => 'w9:p1'
}.freeze

def ownership_fields(overrides = {})
  OWNERSHIP_FIELDS.merge(overrides)
end

class OwnershipStateDirResolutionTest < Minitest::Test
  include StateDirEnv

  def test_resolves_the_repository_state_directory_without_the_environment_variable
    with_state_dir(nil) do
      assert_equal Riddim::Ownership::DEFAULT_STATE_DIR, Riddim::Ownership.state_dir
    end
  end

  def test_resolves_the_repository_state_directory_for_an_empty_environment_value
    with_state_dir('') do
      assert_equal Riddim::Ownership::DEFAULT_STATE_DIR, Riddim::Ownership.state_dir
    end
  end

  def test_resolves_a_nonempty_environment_value
    with_state_dir('/tmp/riddim-lab') do
      assert_equal '/tmp/riddim-lab', Riddim::Ownership.state_dir
    end
  end
end

class OwnershipPathTest < Minitest::Test
  include StateDirEnv

  def test_names_the_record_after_the_agent
    with_state_dir('/tmp/riddim-lab') do
      assert_equal '/tmp/riddim-lab/worker.meta', Riddim::Ownership.record_path('worker')
    end
  end

  def test_names_the_lock_like_firstmates_meta_lock
    with_state_dir('/tmp/riddim-lab') do
      assert_equal '/tmp/riddim-lab/.meta-worker.lock', Riddim::Ownership.lock_path('worker')
    end
  end

  def test_refuses_an_invalid_agent_name
    assert_raises(Riddim::Ownership::InvalidValue) { Riddim::Ownership.record_path('Worker') }
  end
end

class OwnershipStateDirectoryTest < Minitest::Test
  include StateDirEnv

  def test_creates_the_state_directory_owner_only
    Dir.mktmpdir do |dir|
      state = File.join(dir, 'state')
      with_state_dir(state) { Riddim::Ownership.ensure_state_dir }

      assert_equal 0o700, File.stat(state).mode & 0o777
    end
  end

  def test_tightens_an_existing_state_directory_to_owner_only
    Dir.mktmpdir do |dir|
      state = File.join(dir, 'state')
      FileUtils.mkdir(state)
      FileUtils.chmod(0o755, state)
      with_state_dir(state) { Riddim::Ownership.ensure_state_dir }

      assert_equal 0o700, File.stat(state).mode & 0o777
    end
  end

  def test_refuses_a_state_path_that_is_a_file
    Dir.mktmpdir do |dir|
      state = File.join(dir, 'state')
      File.write(state, 'not a directory')

      with_state_dir(state) do
        assert_raises(Riddim::Ownership::Error) { Riddim::Ownership.ensure_state_dir }
      end
    end
  end

  def test_refuses_a_symlinked_state_path
    Dir.mktmpdir do |dir|
      FileUtils.mkdir(File.join(dir, 'elsewhere'))
      state = File.join(dir, 'state')
      File.symlink(File.join(dir, 'elsewhere'), state)

      with_state_dir(state) do
        assert_raises(Riddim::Ownership::Error) { Riddim::Ownership.ensure_state_dir }
      end
    end
  end
end

class OwnershipSerializationTest < Minitest::Test
  def test_serializes_the_firstmate_fields_in_order
    assert_equal OWNERSHIP_BYTES, Riddim::Ownership.serialize(ownership_fields)
  end

  def test_rejects_a_value_with_a_newline
    assert_raises(Riddim::Ownership::InvalidValue) do
      Riddim::Ownership.serialize(ownership_fields('model' => "openrouter/m\n2"))
    end
  end

  def test_rejects_a_value_with_a_carriage_return
    assert_raises(Riddim::Ownership::InvalidValue) do
      Riddim::Ownership.serialize(ownership_fields('model' => "openrouter/m\r2"))
    end
  end

  def test_rejects_an_empty_value
    assert_raises(Riddim::Ownership::InvalidValue) do
      Riddim::Ownership.serialize(ownership_fields('effort' => ''))
    end
  end

  def test_rejects_a_missing_field
    fields = ownership_fields
    fields.delete('effort')

    assert_raises(Riddim::Ownership::InvalidValue) { Riddim::Ownership.serialize(fields) }
  end
end

class OwnershipParsingTest < Minitest::Test
  def test_parses_the_published_bytes_back
    assert_equal ownership_fields, Riddim::Ownership.parse(OWNERSHIP_BYTES)
  end

  def test_rejects_bytes_without_a_trailing_newline
    assert_raises(Riddim::Ownership::InvalidRecord) { Riddim::Ownership.parse(OWNERSHIP_BYTES.chomp) }
  end

  def test_rejects_an_unknown_field_line
    bytes = OWNERSHIP_BYTES.sub("endpoint_task_id=worker\n", "endpoint_task_id=worker\nkind=ship\n")

    assert_raises(Riddim::Ownership::InvalidRecord) { Riddim::Ownership.parse(bytes) }
  end

  def test_rejects_a_blank_line
    bytes = OWNERSHIP_BYTES.sub("endpoint_task_id=worker\n", "endpoint_task_id=worker\n\n")

    assert_raises(Riddim::Ownership::InvalidRecord) { Riddim::Ownership.parse(bytes) }
  end

  def test_rejects_a_duplicate_field
    bytes = OWNERSHIP_BYTES.sub("endpoint_task_id=worker\n", "endpoint_task_id=worker\nendpoint_task_id=worker\n")

    assert_raises(Riddim::Ownership::InvalidRecord) { Riddim::Ownership.parse(bytes) }
  end

  def test_rejects_a_missing_field
    bytes = OWNERSHIP_BYTES.sub("effort=max\n", '')

    assert_raises(Riddim::Ownership::InvalidRecord) { Riddim::Ownership.parse(bytes) }
  end

  def test_rejects_a_value_with_a_control_character
    bytes = OWNERSHIP_BYTES.sub('effort=max', "effort=m\tx")

    assert_raises(Riddim::Ownership::InvalidRecord) { Riddim::Ownership.parse(bytes) }
  end

  def test_rejects_a_record_that_is_not_valid_utf8
    assert_raises(Riddim::Ownership::InvalidRecord) { Riddim::Ownership.parse("\xFF\n".b) }
  end

  def test_rejects_an_empty_record
    assert_raises(Riddim::Ownership::InvalidRecord) { Riddim::Ownership.parse('') }
  end
end

class OwnershipSpawnGenTest < Minitest::Test
  def test_mints_a_firstmate_shaped_incarnation_token
    assert_match(/\As\d+\.\d+\.\d+\z/, Riddim::Ownership.fresh_spawn_gen)
  end

  def test_mints_the_token_from_this_process
    assert_match(/\As\d+\.#{Process.pid}\.\d+\z/, Riddim::Ownership.fresh_spawn_gen)
  end
end

class OwnershipLockTest < Minitest::Test
  include StateDirEnv
  include UmaskEnv

  def test_refuses_a_symlinked_per_name_lock
    Dir.mktmpdir do |dir|
      state = File.join(dir, 'state')
      Dir.mkdir(state)
      File.symlink(File.join(dir, 'elsewhere.lock'), File.join(state, '.meta-worker.lock'))

      with_state_dir(state) do
        assert_raises(Riddim::Ownership::Error) do
          Riddim::Ownership.with_lock('worker') { raise 'the locked block must not run' }
        end
      end
    end
  end

  def test_creates_the_per_name_lock_owner_only
    Dir.mktmpdir do |dir|
      state = File.join(dir, 'state')
      Dir.mkdir(state)
      with_state_dir(state) { Riddim::Ownership.with_lock('worker') { nil } }

      assert_equal 0o600, File.stat(File.join(state, '.meta-worker.lock')).mode & 0o777
    end
  end

  def test_creates_the_per_name_lock_owner_only_under_a_restrictive_umask
    Dir.mktmpdir do |dir|
      state = File.join(dir, 'state')
      Dir.mkdir(state)
      with_umask(0o777) do
        with_state_dir(state) { Riddim::Ownership.with_lock('worker') { nil } }
      end

      assert_equal 0o600, File.stat(File.join(state, '.meta-worker.lock')).mode & 0o777
    end
  end
end

class OwnershipPublicationTest < Minitest::Test
  include UmaskEnv

  def ignore_ownership_error
    yield
  rescue Riddim::Ownership::Error
    nil
  end

  def test_publishes_the_record_bytes
    Dir.mktmpdir do |dir|
      path = File.join(dir, 'worker.meta')
      Riddim::Ownership.publish(path, OWNERSHIP_BYTES)

      assert_equal OWNERSHIP_BYTES, File.read(path)
    end
  end

  def test_publishes_the_record_owner_only
    Dir.mktmpdir do |dir|
      path = File.join(dir, 'worker.meta')
      Riddim::Ownership.publish(path, OWNERSHIP_BYTES)

      assert_equal 0o600, File.stat(path).mode & 0o777
    end
  end

  def test_publishes_the_record_owner_only_under_a_restrictive_umask
    Dir.mktmpdir do |dir|
      path = File.join(dir, 'worker.meta')
      with_umask(0o777) { Riddim::Ownership.publish(path, OWNERSHIP_BYTES) }

      assert_equal 0o600, File.stat(path).mode & 0o777
    end
  end

  def test_link_refuses_to_replace_a_record_that_appears_after_staging
    Dir.mktmpdir do |dir|
      path = File.join(dir, 'worker.meta')
      temp = File.join(dir, '.worker.meta.spawn')
      Riddim::Ownership.stage_record(temp, OWNERSHIP_BYTES)
      File.write(path, 'claimed during publication')

      assert_raises(Riddim::Ownership::Error) { Riddim::Ownership.link_no_replace(temp, path) }
    end
  end

  def test_link_leaves_a_record_that_appears_after_staging_untouched
    Dir.mktmpdir do |dir|
      path = File.join(dir, 'worker.meta')
      temp = File.join(dir, '.worker.meta.spawn')
      Riddim::Ownership.stage_record(temp, OWNERSHIP_BYTES)
      File.write(path, 'claimed during publication')
      ignore_ownership_error { Riddim::Ownership.link_no_replace(temp, path) }

      assert_equal 'claimed during publication', File.read(path)
    end
  end

  def test_leaves_no_temporary_file_behind
    Dir.mktmpdir do |dir|
      path = File.join(dir, 'worker.meta')
      Riddim::Ownership.publish(path, OWNERSHIP_BYTES)

      assert_equal ['worker.meta'], Dir.children(dir).sort
    end
  end

  def test_refuses_to_overwrite_an_existing_record
    Dir.mktmpdir do |dir|
      path = File.join(dir, 'worker.meta')
      File.write(path, 'existing')

      assert_raises(Riddim::Ownership::Error) { Riddim::Ownership.publish(path, OWNERSHIP_BYTES) }
    end
  end

  def test_leaves_the_existing_record_untouched_after_a_refusal
    Dir.mktmpdir do |dir|
      path = File.join(dir, 'worker.meta')
      File.write(path, 'existing')
      begin
        Riddim::Ownership.publish(path, OWNERSHIP_BYTES)
      rescue Riddim::Ownership::Error
        nil
      end

      assert_equal 'existing', File.read(path)
    end
  end
end

class OwnershipRemovalIdentityTest < Minitest::Test
  def test_removes_a_record_still_owned_by_this_spawn
    Dir.mktmpdir do |dir|
      path = File.join(dir, 'worker.meta')
      File.write(path, OWNERSHIP_BYTES)

      assert Riddim::Ownership.remove_if_unchanged(path, 's1767200000.4242.7')
    end
  end

  def test_retains_a_record_owned_by_another_spawn
    Dir.mktmpdir do |dir|
      path = File.join(dir, 'worker.meta')
      File.write(path, OWNERSHIP_BYTES)

      refute Riddim::Ownership.remove_if_unchanged(path, 's1767200000.4242.8')
    end
  end

  def test_retains_a_malformed_record
    Dir.mktmpdir do |dir|
      path = File.join(dir, 'worker.meta')
      File.write(path, "spawn_gen=s1767200000.4242.7\nnot a record\n")

      refute Riddim::Ownership.remove_if_unchanged(path, 's1767200000.4242.7')
    end
  end

  def test_retains_a_symlink_at_the_record_path
    Dir.mktmpdir do |dir|
      target = File.join(dir, 'elsewhere')
      File.write(target, OWNERSHIP_BYTES)
      path = File.join(dir, 'worker.meta')
      File.symlink(target, path)

      refute Riddim::Ownership.remove_if_unchanged(path, 's1767200000.4242.7')
    end
  end

  def test_never_removes_the_target_of_a_symlink_at_the_record_path
    Dir.mktmpdir do |dir|
      target = File.join(dir, 'elsewhere')
      File.write(target, OWNERSHIP_BYTES)
      path = File.join(dir, 'worker.meta')
      File.symlink(target, path)
      Riddim::Ownership.remove_if_unchanged(path, 's1767200000.4242.7')

      assert_equal OWNERSHIP_BYTES, File.read(target)
    end
  end

  def test_detects_a_record_replaced_after_its_descriptor_was_opened
    Dir.mktmpdir do |dir|
      path = File.join(dir, 'worker.meta')
      File.write(path, OWNERSHIP_BYTES)
      before = File.stat(path)
      incoming = File.join(dir, 'incoming')
      File.write(incoming, 'replaced mid-check')
      File.rename(incoming, path)

      refute Riddim::Ownership.same_regular_file?(before, File.stat(path))
    end
  end

  def test_needs_no_removal_when_no_record_exists
    Dir.mktmpdir do |dir|
      assert Riddim::Ownership.remove_if_unchanged(File.join(dir, 'worker.meta'), 's1767200000.4242.7')
    end
  end
end
