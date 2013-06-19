# https://gist.github.com/jimweirich/5813834
require 'rbconfig'

module Nyara
  # Based on a script at:
  #   http://stackoverflow.com/questions/891537/ruby-detect-number-of-cpus-installed
  class CpuCounter
    def self.count
      new.count
    end

    def count
      case RbConfig::CONFIG['host_os']
      when /darwin9/
        `hwprefs cpu_count`.to_i
      when /darwin/
        darwin_count
      when /linux/
        linux_count
      when /freebsd/
        freebsd_count
      when /mswin|mingw/
        win32_count
      end
    end

    def darwin_count
      if cmd = resolve_command('hwprefs')
        `#{cmd} thread_count`.to_i
      elsif cmd = resolve_command('sysctl')
        `#{cmd} -n hw.ncpu`.to_i
      end
    end

    def linux_count
      open('/proc/cpuinfo') { |f| f.readlines }.grep(/processor/).size
    end

    def freebsd_count
      if cmd = resolve_command('sysctl')
        `#{cmd} -n hw.ncpu`.to_i
      end
    end

    def win32_count
      require 'win32ole'
      wmi = WIN32OLE.connect("winmgmts://")
      cpu = wmi.ExecQuery("select NumberOfCores from Win32_Processor") # TODO count hyper-threaded in this
      cpu.to_enum.first.NumberOfCores
    end

    def resolve_command(command)
      try_command("/sbin/", command) || try_command("/usr/sbin/", command) || in_path_command(command)
    end

    def in_path_command(command)
      `which #{command}` != '' ? command : nil
    end

    def try_command(dir, command)
      path = dir + command
      File.exist?(path) ? path : nil
    end
  end
end
