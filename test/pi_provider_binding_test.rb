# frozen_string_literal: true

require 'minitest/autorun'
require 'bundler'
require 'json'
require 'open3'
require 'socket'
require 'tmpdir'
require_relative '../lib/riddim/profile'
require_relative '../lib/riddim/task_brief'
require_relative '../scripts/pi_stall_server'

# Riddim's staged task launch run by the real Pi resolver against loopback
# providers. "lab-router" plays OpenRouter: authenticated, and its catalog
# holds the ID "lab-bridge/opus". No request ever leaves the machine.
class PiProviderBindingTest < Minitest::Test
  BASE_ARGUMENTS = %w[--mode json --print --no-tools --no-skills --no-prompt-templates --no-context-files
                      --no-extensions --approve --no-session].freeze

  def setup
    @real_pi = installed_pi
    skip 'Pi executable unavailable on PATH' unless @real_pi
    @root = Dir.mktmpdir('riddim-provider-binding-')
    @servers = { 'bridge' => TCPServer.new('127.0.0.1', 0), 'router' => TCPServer.new('127.0.0.1', 0) }
    @contacts = Queue.new
    @responders = @servers.map { |name, server| respond(name, server) }
    install_pi_shim
  end

  def teardown
    @responders&.each(&:kill)
    @servers&.each_value(&:close)
    FileUtils.remove_entry(@root) if @root
  end

  def installed_pi
    ENV.fetch('PATH').split(File::PATH_SEPARATOR).map { |dir| File.join(dir, 'pi') }
       .find { |path| File.file?(path) && File.executable?(path) }
  end

  def respond(name, server)
    Thread.new { loop { answer(name, server) } }
  end

  def answer(name, server)
    socket = PiStallLab::LabServer.receive_request(server)
    @contacts << name
    PiStallLab::LabServer.send_ok(socket)
  rescue Errno::EPIPE, Errno::ECONNRESET
    nil
  ensure
    socket&.close
  end

  # The staged script resolves `pi` on PATH; the shim only adds offline,
  # non-interactive flags ahead of Riddim's own arguments.
  def install_pi_shim
    @bin = File.join(@root, 'bin')
    Dir.mkdir(@bin)
    File.write(File.join(@bin, 'pi'), "#!/bin/sh\nexec #{@real_pi.dump} #{BASE_ARGUMENTS.join(' ')} \"$@\"\n")
    File.chmod(0o755, File.join(@bin, 'pi'))
  end

  def configure(bridge_authenticated:)
    provider = lambda do |name, ids, authenticated|
      config = { baseUrl: "http://127.0.0.1:#{@servers.fetch(name).addr[1]}/v1", api: 'openai-completions',
                 models: ids.map { |id| { id: id, contextWindow: 128_000, maxTokens: 64 } } }
      authenticated ? config.merge(apiKey: 'dummy') : config
    end
    File.write(File.join(@root, 'models.json'),
               JSON.generate(providers: { 'lab-bridge' => provider.call('bridge', ['opus'], bridge_authenticated),
                                          'lab-router' => provider.call('router', ['lab-bridge/opus'], true) }))
  end

  def staged_launch(model)
    brief_path = File.join(@root, 'worker.brief')
    File.write(brief_path, "Reply briefly.\n")
    profile = Riddim::AgentProfile.new(harness: 'pi', model: model, effort: 'low')
    with_shim_path { Riddim::TaskBrief.launch_source(Riddim::TaskBrief::Brief.new(brief_path, ''), profile) }
  end

  def launch(model)
    source = staged_launch(model)
    environment = { 'PI_CODING_AGENT_DIR' => @root, 'PI_OFFLINE' => '1', 'PI_TELEMETRY' => '0',
                    'PATH' => "#{@bin}:#{ENV.fetch('PATH')}" }
    _, status = Bundler.with_unbundled_env do
      Open3.capture2e(environment, 'timeout', '60', '/bin/sh', '-c', source, chdir: @root)
    end
    [status.exitstatus, contacted]
  end

  def with_shim_path
    old_path = ENV.fetch('PATH')
    ENV['PATH'] = "#{@bin}:#{old_path}"
    yield
  ensure
    ENV['PATH'] = old_path
  end

  def contacted
    names = []
    names << @contacts.pop until @contacts.empty?
    names.uniq
  end

  def test_unavailable_allowlisted_provider_fails_instead_of_reaching_a_look_alike
    configure(bridge_authenticated: false)

    assert_equal [1, []], launch('lab-bridge/opus')
  end

  def test_available_allowlisted_provider_serves_its_own_model
    configure(bridge_authenticated: true)

    assert_equal [0, ['bridge']], launch('lab-bridge/opus')
  end

  def test_a_slashed_model_id_stays_on_its_listed_provider
    configure(bridge_authenticated: false)

    assert_equal [0, ['router']], launch('lab-router/lab-bridge/opus')
  end
end
