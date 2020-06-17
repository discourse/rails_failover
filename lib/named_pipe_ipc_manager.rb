# frozen_string_literal: true
require 'fileutils'

class NamedPipeIpcManager
  REGISTER_COMMAND = 'register'

  def initialize(tmp_dir: "/tmp/named_pipes", &block)
    @tmp_dir = tmp_dir
    @ancestor_pid = Process.pid
    @parent_filename = File.join(@tmp_dir, "parent_#{@ancestor_pid}").to_s
    @child_filenames = []
    @block = block

    FileUtils.mkdir(@tmp_dir) unless Dir.exists?(@tmp_dir)

    unless File.exists?(@parent_filename)
      File.mkfifo(@parent_filename)
    end

    start
  end

  def start
    @parent_thread ||= begin
      Thread.new do
        read_io = File.open(@parent_filename, "r+")

        loop do
          begin
            input = read_io.read_nonblock(1000)
          rescue IO::WaitReadable
            IO.select([read_io])
            retry
          rescue IO::EAGAINWaitReadable
            retry
          end

          command, message = input.split(":")

          case command
          when REGISTER_COMMAND
            @child_filenames << message
          else
            @child_filenames.each do |filename|
              File.write(filename, input)
            end
          end
        end
      ensure
        read_io.close if read_io
      end
    end
  end

  def after_fork
    @child_thread ||= begin
      child_filename = File.join(@tmp_dir, "child_#{Process.pid}").to_s

      unless File.exists?(child_filename)
        File.mkfifo(child_filename)
      end

      File.write(@parent_filename, "#{REGISTER_COMMAND}:#{child_filename}")

      Thread.new do
        child_io = File.open(child_filename, "r+")

        loop do
          begin
            input = child_io.read_nonblock(1000)
          rescue IO::WaitReadable
            IO.select([child_io])
            retry
          rescue IO::EAGAINWaitReadable
            retry
          end

          @block.call(input)
        end
      ensure
        child_io&.close
      end
    end
  end

  def publish(message)
    File.write(@parent_filename, message)
  end

  def started?
    @parent_thread&.alive?
  end
end
