# frozen_string_literal: true

Given('Pi records its exact launch arguments and profile') do
  @configured_profile = File.binread(File.join(@environment.fetch('RIDDIM_CONFIG_DIR'), 'agent-profile'))
  executable = File.join(@herdr_directory, 'pi-bin', 'pi')
  @pi_observation = File.join(@herdr_directory, 'pi-arguments.json')
  File.write(executable, <<~RUBY)
    #!/usr/bin/ruby
    require 'json'
    record = File.read(File.join(ENV.fetch('RIDDIM_STATE_DIR'), 'worker.meta'))
    File.write(#{@pi_observation.dump}, JSON.generate(argv: ARGV, record: record))
    abort 'model was interpreted as shell code' if File.exist?('PWNED')
  RUBY
  File.write(File.join(@herdr_directory, 'execute-task-launch'), '')
end

Then('Pi and the ownership record select model {string} and effort {string} without changing config') do |model, effort|
  observation = JSON.parse(File.read(@pi_observation)) if File.file?(@pi_observation)
  record = File.read(scenario_record_path('worker')) if File.file?(scenario_record_path('worker'))
  brief = File.read(File.join(scenario_state_dir, 'worker.brief')) if record
  profile = File.binread(File.join(@environment.fetch('RIDDIM_CONFIG_DIR'), 'agent-profile'))
  assert_equal [true, ['--model', model, '--thinking', effort, brief], record, true, true, @configured_profile],
               [@status.success?, observation && observation['argv'], observation && observation['record'],
                record&.include?("\nmodel=#{model}\n"), record&.include?("\neffort=#{effort}\n"), profile], @stderr
end

Then('start refuses before creating any worker assets or invoking Herdr') do
  branches, status = Open3.capture2('git', '-C', @project, 'branch', '--list', 'riddim/*')
  assert_equal [false, false, [], [], true, ''],
               [@status.success?, File.exist?(@worktree), Dir.glob(File.join(scenario_state_dir, '*')),
                herdr_invocations, status.success?, branches], @stderr
end

When('I try a model containing {string}') do |kind|
  models = { 'newline' => "provider/model\nforged=value", 'carriage return' => "provider/model\r",
             'tab' => "provider/\tmodel", 'escape' => "provider/\emodel", 'delete' => "provider/\x7fmodel",
             'empty' => '', 'invalid UTF-8' => "provider/\xff".b }
  @stdout, @stderr, @status = run_riddim('start', 'worker', '--worktree', '--task-file', 'task.md',
                                         '--mode', 'local-only', '--model', models.fetch(kind))
end

Given('Herdr records exact native agent arguments for distinct endpoints') do
  @configured_profile = File.binread(File.join(@environment.fetch('RIDDIM_CONFIG_DIR'), 'agent-profile'))
  install_fake_herdr(<<~RUBY)
    require 'json'
    case ARGV[0, 2]
    when ['workspace', 'create']
      File.open(File.expand_path('sequence', __dir__), File::RDWR | File::CREAT, 0600) do |file|
        file.flock(File::LOCK_EX)
        number = file.read.to_i + 1
        file.rewind
        file.write(number.to_s)
        body = JSON.parse(#{CANNED_CREATE_RESPONSE.dump})
        result = body.fetch('result')
        result['workspace']['workspace_id'] = "w\#{number}"
        result['tab'].merge!('workspace_id' => "w\#{number}", 'tab_id' => "w\#{number}:t1")
        result['root_pane'].merge!('workspace_id' => "w\#{number}", 'tab_id' => "w\#{number}:t1",
                                   'pane_id' => "w\#{number}:p1")
        puts JSON.generate(body)
      end
    when ['agent', 'start']
      File.write(File.expand_path("\#{ARGV[2]}.argv.json", __dir__), JSON.generate(ARGV))
    else abort "unexpected command: \#{ARGV.inspect}"
    end
  RUBY
end

When('I start two differently configured workers and then a default worker') do
  selections = [['alpha', '--model', 'provider/alpha', '--effort', 'high'],
                ['beta', '--effort=low', '--model=provider/beta']]
  @model_starts = selections.map { |args| Thread.new { run_riddim('start', *args) } }.map(&:value)
  @model_starts << run_riddim('start', 'gamma')
end

Then('all three native launches match their independent recorded profiles') do
  expected = [['alpha', 'provider/alpha', 'high'], ['beta', 'provider/beta', 'low'],
              ['gamma', 'openrouter/z-ai/glm-5.3-flash', 'max']]
  actual = expected.map do |name, _model, _effort|
    record = File.readlines(scenario_record_path(name), chomp: true).to_h { |line| line.split('=', 2) }
    argv = JSON.parse(File.read(File.join(@herdr_directory, "#{name}.argv.json")))
    [name, record.fetch('model'), record.fetch('effort'),
     argv == ['agent', 'start', name, '--kind', 'pi', '--pane', record.fetch('herdr_pane_id'), '--',
              '--model', record.fetch('model'), '--thinking', record.fetch('effort')]]
  end
  profile = File.binread(File.join(@environment.fetch('RIDDIM_CONFIG_DIR'), 'agent-profile'))
  assert_equal [expected.map { |row| [*row, true] }, [true, true, true], @configured_profile, 3],
               [actual, @model_starts.map { |result| result.last.success? }, profile,
                expected.map do |name, *_|
                  File.read(scenario_record_path(name))[/^herdr_pane_id=(.+)$/, 1]
                end.uniq.length], @model_starts.inspect
end
