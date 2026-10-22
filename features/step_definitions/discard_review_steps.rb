# frozen_string_literal: true

Given('the worker committed sensitive-looking fixtures') do
  %w[.env.example config/credentials.yml.enc spec/fixtures/server.pem].each do |path|
    absolute = File.join(@worktree, path)
    FileUtils.mkdir_p(File.dirname(absolute))
    File.write(absolute, "public fixture\n")
    File.utime(Time.at(1), Time.at(1), absolute)
  end
  dirty_git!('add', '.')
  dirty_git!('commit', '-m', 'public sensitive-looking fixtures')
  @worker_tip = dirty_git!('rev-parse', 'HEAD').strip
end

Given('a sensitive-looking fixture changes in {string}') do |kind|
  path = File.join(@worktree, '.env.example')
  stat = File.stat(path)
  case kind
  when 'deleted' then File.unlink(path)
  when 'untracked' then File.write(File.join(@worktree, '.env.private'), 'private fixture')
  else
    File.write(path, "private value!\n")
    dirty_git!('add', '.env.example') if kind == 'staged'
    if kind == 'preserved stat'
      dirty_git!('config', 'core.trustctime', 'false')
      dirty_git!('config', 'core.checkStat', 'minimal')
      File.utime(stat.atime, stat.mtime, path)
      raise 'fixture must be stat-cache clean' unless dirty_git!('status', '--porcelain', '--', '.env.example').empty?
    end
  end
end

Given('the worker untracks a file without removing its contents') do
  dirty_git!('rm', '--cached', 'tracked.txt')
end

Then('discard explicitly refuses duplicate status paths without mutation') do
  assert_equal [false, true, true, true, "worker change\n", false],
               [@status.success?, @stderr.include?('duplicate Git status paths'),
                File.file?(scenario_record_path('worker')), File.directory?(@worktree),
                File.read(File.join(@worktree, 'tracked.txt')),
                herdr_invocations.any? { |line| line.include?('pane close') }], @stderr
end
