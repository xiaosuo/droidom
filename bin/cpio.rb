#!/usr/bin/env ruby

require 'find'

# only newc format is supported, and it is enough for the initramfs
module Cpio
  Magic = '070701'
  Magic2 = '070702' # it is used by linux kernel

  S_IFMT = 0170000
  S_IFLNK = 0120000
  S_IFREG = 0100000
  S_IFDIR = 0040000

  # pack all the files in the current directory into a cpio file
  def Cpio.pack(filename, verbose = false)
    file = File.new(filename, "wb")
    Find.find('.') do |name|
      next if name == '.'
      puts name if verbose
      stat = File.stat(name)
      hdr = sprintf("%s%08X%08X%08X%08X%08X%08X%08X%08X%08X%08X%08X%08X%08X",
        Magic, stat.ino, stat.mode, 0, 0, 1, 0,
        stat.directory? ? 0 : stat.size, 0, 0, 0, 0,
        name.size + 1, 0)
      file.write(hdr)
      file.write(name)
      namesize_align = ((name.size + 1 + 2 + 3) & ~3) - 2
      file.write("\x00" * (namesize_align - name.size))
      if stat.directory?
        body = nil
      elsif stat.symlink?
        body = File.readlink(name)
      elsif stat.file?
        body = File.read(name)
      else
        raise "unsupported file type: #{name}"
      end
      if body
        bodysize_align = (body.size + 3) & ~3
        file.write(body)
        if (bodysize_align != body.size)
          file.write("\x00" * (bodysize_align - body.size))
        end
      end
    end
    hdr = sprintf("%s%08X%08X%08X%08X%08X%08X%08X%08X%08X%08X%08X%08X%08X",
      Magic, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 11, 0)
    file.write(hdr)
    file.write("TRAILER!!!\x00\x00\x00\x00")
    file.close
  end

  # unpack all the files in a cpio file into the current directory
  def Cpio.unpack(filename, verbose = false)
    file = File.new(filename, "rb")
    while true
      magic = file.read(6)
      raise "invalid file: #{filename}" if (magic != Magic && magic != Magic2)
      ino, mode, uid, gid, nlink, mtime, filesize, devmajor, devminor, \
        rdevmajor, rdevminor, namesize, check = \
          file.read(8 * 13).scan(/.{8}/).collect!{ |x| x.hex }
      namesize_align = ((namesize + 2 + 3) & ~3) - 2
      filesize_align = (filesize + 3) & ~3
      name = file.read(namesize - 1)
      break if (name == 'TRAILER!!!')
      file.read(namesize_align - namesize + 1)
      name.sub!(/^\//, '') # don't use absolute path
      puts name if verbose
      if filesize > 0
        body = file.read(filesize) 
      else
        body = nil
      end
      file.read(filesize_align - filesize) unless filesize_align == filesize
      dirname = File.dirname(name)
      Dir.mkdir(dirname) unless File.exists?(dirname)
      case mode & S_IFMT
      when S_IFLNK
        File.symlink(body, name)
      when S_IFREG
        nfile = File.new(name, "w")
        nfile.write(body) if body
        nfile.close
      when S_IFDIR
        Dir.mkdir(name) unless File.directory?(name)
      else
        raise "unsupported file type: #{name}"
      end
      File.chmod(mode & 0777, name) unless mode & S_IFMT == S_IFLNK
    end
    file.close
  end
end

if __FILE__ == $0
  if ARGV.size != 2
    puts "Usage: #{$0} pack|unpack filename"
    exit(1)
  end
  if ARGV[0] == 'pack'
    Cpio.pack(ARGV[1], true)
  else
    Cpio.unpack(ARGV[1], true)
  end
end
