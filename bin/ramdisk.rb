#!/usr/bin/env ruby

require 'zlib'
require 'tempfile'
require File.join(File.dirname(__FILE__), 'cpio')

module RamDisk
  def RamDisk.pack(filename = 'initrd.gz', verbose = false)
    Zlib::GzipWriter.open(filename, Zlib::BEST_COMPRESSION) do |file|
      tmp_file = Tempfile.new('initrd')
      Dir.chdir('initrd')
      Cpio.pack(tmp_file.path, verbose)
      Dir.chdir('..')
      file.write(tmp_file.read)
      tmp_file.close
      tmp_file.unlink
    end
  end

  def RamDisk.unpack(filename = 'initrd.gz', verbose = false)
    Zlib::GzipReader.open(filename) do |file|
      tmp_file = Tempfile.new('initrd')
      tmp_file.write(file.read)
      tmp_file.close
      Dir.mkdir('initrd') unless File.directory?('initrd')
      Dir.chdir('initrd')
      Cpio.unpack(tmp_file.path, verbose)
      Dir.chdir('..')
      tmp_file.unlink
    end
  end
end

if __FILE__ == $0
  unless ARGV.size == 1 || ARGV.size == 2
    puts "Usage: #{$0} pack|unpack [initrd.gz]"
    exit(1)
  end
  if ARGV.size == 2
    filename = ARGV[1]
  else
    filename = 'initrd.gz'
  end
  if ARGV[0] == 'pack'
    RamDisk.pack(filename, true)
  else
    RamDisk.unpack(filename, true)
  end
end
