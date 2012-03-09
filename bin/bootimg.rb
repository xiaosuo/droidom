#!/usr/bin/env ruby

require "sha1"
require File.join(File.dirname(__FILE__), 'ramdisk')

module BootImg
  def BootImg.align(x, size)
    size = size - 1
    (x + size) & ~size
  end

  def BootImg.read_padding(file, x, size)
    x_align = align(x, size)
    file.read(x_align - x) if x_align != x
  end

  def BootImg.write_padding(file, x, size)
    x_align = align(x, size)
    file.write("\x00" * (x_align - x)) if x_align != x
  end

  def BootImg.unpack(img, verbose = false)
    file = File.new(img, "rb")
  
    # parse the header
    hdr = file.read(584)
    magic, kernel_size, kernel_addr, ramdisk_size, ramdisk_addr, \
      second_size, second_addr, tags_addr, page_size, unused1, unused2, \
      name, cmdline, id = hdr.unpack("a8VVVVVVVVVVa16a512a8")
    return false if magic != "ANDROID!"
    name.gsub!(/\x00.*/, '')
    cmdline.gsub!(/\x00.*/, '')
    padding_size = page_size
    # remove the padding bytes
    file.read(page_size - 584)
    # padding_size may be not equal to the page size, check it
    if page_size == 2048
      check = file.read(2048)
      if check.slice(36, 4) == "\x18\x28\x6f\x01"
        file.seek(-2048, IO::SEEK_CUR)
      else
        padding_size = 4096
      end
    end

    kernel_data = file.read(kernel_size)
    read_padding(file, kernel_size, padding_size)
    ramdisk_data = file.read(ramdisk_size)
    read_padding(file, ramdisk_size, padding_size)
    if (second_size != 0)
      second_data = file.read(second_size)
      read_padding(file, second_size, padding_size)
    end

    sha = SHA1.new
    sha << kernel_data
    sha << [kernel_size].pack('V')
    sha << ramdisk_data
    sha << [ramdisk_size].pack('V')
    sha << second_data if second_size != 0
    sha << [second_size].pack('V')
    if sha.digest.slice(0, 8) != id
      raise 'invalid checksum'
    end

    Dir.mkdir('boot') unless File.directory?('boot')
    Dir.chdir('boot')
    puts './boot/cfg.rb' if verbose
    File.open("cfg.rb", "w") do |cfg|
      cfg.puts "module Cfg"
      cfg.puts "  Kernel_addr = #{kernel_addr}"
      cfg.puts "  Ramdisk_addr = #{ramdisk_addr}"
      cfg.puts "  Second_addr = #{second_addr}"
      cfg.puts "  Tags_addr = #{tags_addr}"
      cfg.puts "  Page_size = #{page_size}"
      cfg.puts "  Name = \"#{name}\""
      cfg.puts "  Cmdline = \"#{cmdline}\""
      cfg.puts "  Padding_size = #{padding_size}"
      cfg.puts "end"
    end
    puts './boot/zImage' if verbose
    File.open('zImage', 'wb') { |f| f.write(kernel_data) }
    puts './boot/initrd.gz' if verbose
    File.open('initrd.gz', 'wb') { |f| f.write(ramdisk_data) }
    RamDisk.unpack('initrd.gz', verbose)
    File.unlink('initrd.gz')
    if second_size > 0
      puts './boot/second.img' if verbose
      File.open('second.img', 'wb') { |f| f.write(second_data) }
    end
    Dir.chdir('..')
  end

  def BootImg.pack(img, verbose = false)
    Dir.chdir('boot')
    if File.exists?('second.img')
      puts './boot/second.img' if verbose
      second_data = IO.read('second.img')
    else
      second_data = nil
    end
    RamDisk.pack('initrd.gz', verbose)
    puts './boot/initrd.gz' if verbose
    ramdisk_data = IO.read('initrd.gz')
    puts './boot/zImage' if verbose
    kernel_data = IO.read('zImage')
    puts './boot/cfg.rb' if verbose
    load 'cfg.rb'
    Dir.chdir('..')

    sha = SHA1.new
    sha << kernel_data
    sha << [kernel_data.size].pack('V')
    sha << ramdisk_data
    sha << [ramdisk_data.size].pack('V')
    if second_data
      sha << second_data
      sha << [second_data.size].pack('V')
    else
      sha << [0].pack('V')
    end

    hdr = ['ANDROID!', kernel_data.size, Cfg::Kernel_addr, ramdisk_data.size,
           Cfg::Ramdisk_addr, second_data ? second_data.size : 0,
           Cfg::Second_addr, Cfg::Tags_addr, Cfg::Page_size, 0, 0,
           Cfg::Name, Cfg::Cmdline, sha.digest].pack('a8VVVVVVVVVVa16a512a20')
    File.open(img, 'wb') do |file|
      file.write(hdr)
      write_padding(file, hdr.size, Cfg::Padding_size)
      file.write(kernel_data)
      write_padding(file, kernel_data.size, Cfg::Padding_size)
      file.write(ramdisk_data)
      write_padding(file, ramdisk_data.size, Cfg::Padding_size)
      if second_data
        file.write(second_data)
        write_padding(file, second_data.size, Cfg::Padding_size)
      end
    end
  end
end

if __FILE__ == $0
  if ARGV.size == 1
    filename = 'boot.img'
  elsif ARGV.size == 2
    filename = ARGV[1]
  else
    puts "Usage: #{$0} pack|unpack [boot.img]"
    exit(1)
  end
  if ARGV[0] == 'pack'
    BootImg.pack(filename, true)
  else
    BootImg.unpack(filename, true)
  end
end
