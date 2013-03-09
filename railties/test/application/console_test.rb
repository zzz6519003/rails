require 'isolation/abstract_unit'

begin
  require "pty"
rescue LoadError
end

class FullStackConsoleTest < ActiveSupport::TestCase
  def setup
    skip "PTY unavailable" unless defined?(PTY) && PTY.respond_to?(:open)

    build_app
    app_file 'app/models/post.rb', <<-CODE
      class Post < ActiveRecord::Base
      end
    CODE
    system "#{app_path}/bin/rails runner 'Post.connection.create_table :posts'"

    @master, @slave = PTY.open
  end

  def teardown
    teardown_app
  end

  def assert_output(expected, timeout = 1)
    timeout = Time.now + timeout

    output = ""
    until output.include?(expected) || Time.now > timeout
      if IO.select([@master], [], [], 0.1)
        output << @master.read(1)
      end
    end

    p output

    assert output.include?(expected), "#{expected.inspect} expected, but got:\n\n#{output}"
  end

  def write_prompt(command, expected_output = nil)
    @master.puts command
    assert_output command
    assert_output expected_output if expected_output
    assert_output "> "
  end

  def kill(pid)
    Process.kill('QUIT', pid)
    Process.wait(pid)
  rescue Errno::ESRCH
  end

  def spawn_console
    pid = Process.spawn(
      "#{app_path}/bin/rails console --sandbox",
      in: @slave, out: @slave, err: @slave
    )

    assert_output "> ", 30
    pid
  end

  def test_sandbox
    pid = spawn_console

    write_prompt "Post.count", "=> 0"
    write_prompt "Post.create"
    write_prompt "Post.count", "=> 1"

    kill pid

    pid = spawn_console

    write_prompt "Post.count", "=> 0"
    write_prompt "Post.transaction { Post.create; raise }"
    write_prompt "Post.count", "=> 0"
  ensure
    kill pid if pid
  end
end
