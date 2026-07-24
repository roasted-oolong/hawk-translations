require "rails_helper"

RSpec.describe Pipeline::Subprocess do
  def run(cmd, timeout: 5, env: {}, cancel_token: nil, name: "test", stdin: nil)
    described_class.run(cmd, env: env, timeout: timeout, name: name, cancel_token: cancel_token, stdin: stdin)
  end

  describe "a command that exits successfully" do
    it "returns a completed result with exit_code 0 and captured stdout" do
      result = run([ "ruby", "-e", "STDOUT.print 'hello'; STDERR.print 'warn'; exit 0" ])

      expect(result.status).to eq(:completed)
      expect(result.exit_code).to eq(0)
      expect(result.success?).to eq(true)
      expect(result.stdout).to eq("hello")
      expect(result.stderr).to eq("warn")
      expect(result.bytes_stdout).to eq(5)
      expect(result.bytes_stderr).to eq(4)
      expect(result.command_name).to eq("test")
    end
  end

  describe "a command that exits nonzero" do
    it "returns a completed result with success? false" do
      result = run([ "ruby", "-e", "exit 7" ])

      expect(result.status).to eq(:completed)
      expect(result.exit_code).to eq(7)
      expect(result.success?).to eq(false)
    end
  end

  describe "a command killed by an external signal" do
    it "reports a shell-style 128+signal exit_code, not a nil one" do
      result = run([ "ruby", "-e", "Process.kill('KILL', Process.pid); sleep" ])

      expect(result.status).to eq(:completed)
      expect(result.exit_code).to eq(128 + 9)
      expect(result.success?).to eq(false)
    end
  end

  describe "timestamps and duration" do
    it "captures started_at/finished_at and a matching duration" do
      result = run([ "ruby", "-e", "sleep 0.2" ])

      expect(result.finished_at).to be > result.started_at
      expect(result.duration).to be_within(0.3).of(0.2)
    end
  end

  describe "a command that exceeds its timeout" do
    it "kills the process, returning timed_out with a nil exit_code" do
      result = run([ "ruby", "-e", "sleep 5" ], timeout: 0.2)

      expect(result.status).to eq(:timed_out)
      expect(result.exit_code).to be_nil
      expect(result.success?).to eq(false)
    end

    it "terminates forked children too, not just the top process" do
      Dir.mktmpdir do |dir|
        marker = File.join(dir, "child_alive")
        script = <<~RUBY
          child_pid = fork { sleep 5 }
          File.write(#{marker.inspect}, child_pid.to_s)
          Process.detach(child_pid)
          sleep 5
        RUBY

        run([ "ruby", "-e", script ], timeout: 0.3)
        sleep 0.3 # give the killed child's process slot a moment to clear

        child_pid = File.read(marker).to_i
        expect { Process.kill(0, child_pid) }.to raise_error(Errno::ESRCH)
      end
    end
  end

  describe "cancellation via cancel_token" do
    it "kills the process and returns cancelled with a nil exit_code" do
      cancel_token = instance_double("CancelToken")
      call_count = 0
      allow(cancel_token).to receive(:cancelled?) do
        call_count += 1
        call_count > 1
      end

      result = run([ "ruby", "-e", "sleep 5" ], timeout: 30, cancel_token: cancel_token)

      expect(result.status).to eq(:cancelled)
      expect(result.exit_code).to be_nil
    end
  end

  describe "output larger than the OS pipe buffer" do
    it "fully drains stdout without deadlocking" do
      size = 2 * 1024 * 1024 # 2MB, comfortably above the ~64KB pipe buffer
      result = run([ "ruby", "-e", "STDOUT.write('a' * #{size})" ], timeout: 10)

      expect(result.bytes_stdout).to eq(size)
      expect(result.stdout.bytesize).to eq(size)
    end
  end

  describe "env isolation" do
    it "does not leak the parent process's env into the child beyond what env: explicitly lists" do
      begin
        ENV["HAWK_SUBPROCESS_SPEC_MARKER"] = "should-not-leak"
        result = run([ "ruby", "-e", "print ENV['HAWK_SUBPROCESS_SPEC_MARKER'].inspect" ], env: { "FOO" => "bar" })

        expect(result.stdout).to eq("nil")
      ensure
        ENV.delete("HAWK_SUBPROCESS_SPEC_MARKER")
      end
    end

    it "still provides every key explicitly listed in env:" do
      result = run([ "ruby", "-e", "print ENV['FOO']" ], env: { "FOO" => "bar" })

      expect(result.stdout).to eq("bar")
    end
  end

  describe "stdin:" do
    it "pipes the given content to the child's stdin" do
      result = run([ "ruby", "-e", "print STDIN.read" ], stdin: "hello from parent")

      expect(result.stdout).to eq("hello from parent")
    end

    it "closes stdin so the child sees EOF rather than hanging" do
      result = run([ "ruby", "-e", "STDIN.read; STDOUT.print 'saw eof'" ], stdin: "x", timeout: 2)

      expect(result.status).to eq(:completed)
      expect(result.stdout).to eq("saw eof")
    end

    it "writes stdin larger than the OS pipe buffer without deadlocking" do
      size = 2 * 1024 * 1024 # 2MB, comfortably above the ~64KB pipe buffer
      payload = "b" * size

      result = run([ "ruby", "-e", "STDOUT.write(STDIN.read.bytesize.to_s)" ], stdin: payload, timeout: 10)

      expect(result.stdout).to eq(size.to_s)
    end

    it "gives the child an immediately-closed stdin when omitted, same as before this option existed" do
      result = run([ "ruby", "-e", "STDOUT.print STDIN.read.inspect" ])

      expect(result.stdout).to eq("\"\"".dup)
    end
  end

  describe "logging" do
    it "logs only command_name/status/exit_code/duration/byte counts, never full cmd or env" do
      secret_env = { "SUPER_SECRET_TOKEN" => "s3kr1t" }
      messages = []
      allow(Rails.logger).to receive(:info) { |msg| messages << msg }

      run([ "ruby", "-e", "STDOUT.print 'ok'" ], env: secret_env, name: "translate_batch")

      expect(messages).not_to be_empty
      logged = messages.join("\n")
      expect(logged).to include("translate_batch")
      expect(logged).not_to include("s3kr1t")
      expect(logged).not_to include("SUPER_SECRET_TOKEN")
    end
  end
end
