#!/usr/bin/env ruby
#
# inkmake - Makefile inspired export from SVG files using Inkscape as backend
#           with some added smartness.
#
# Copyright (c) 2015 <mattias.wadman@gmail.com>
#
# MIT License:
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in
# all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
# THE SOFTWARE.
#
# Try to stay campatible with Ruby 1.8.7 as its the default ruby
# version included in Mac OS X (at least Lion).
#
# NOTE: Rotation is done using a temporary SVG file that translate and rotate
# a double resolution bitmap and export as a bitmap to the correct resolution.
# This hack is done to get around that Inkscape cant set bitmap oversampling
# mode per file or from command line, default is 2x2 oversampling.
#

require "csv"
require "rexml/document"
require "rexml/xpath"
require "open3"
require "optparse"
require "fileutils"
require "tempfile"
require "uri"
require "pathname"
require "rbconfig"

class Inkmake
  @verbose = false
  @inkscape_path = nil
  class << self
    attr :verbose, :inkscape_path
  end

  class InkscapeUnit
    # 90dpi as reference
    Units = {
      "pt" => 1.25,
      "pc" => 15,
      "mm" => 3.543307,
      "cm" => 35.43307,
      "dm" => 354.3307,
      "m"  => 3543.307,
      "in" => 90,
      "ft" => 1080,
      "uu" => 1 # user unit, 90 dpi
    }

    attr_reader :value, :unit

    def initialize(value, unit="uu")
      case value
      when /^(\d+(?:\.\d+)?)(\w+)?$/ then
        @value = $1.to_f
        @unit = $2
        @unit ||= unit
        @unit = (@unit == "px" or Units.has_key?(@unit)) ? @unit : "uu"
      else
        @value = value.kind_of?(String) ? value.to_f: value
        @unit = unit
      end
    end

    def to_pixels(dpi=90.0)
      return @value.round if @unit == "px"
      ((dpi / 90.0) * Units[@unit] * @value).round
    end

    def to_s
      "%g#{@unit}" % @value
    end

    def scale(f)
      return self if @unit == "px"
      InkscapeUnit.new(@value * f, @unit)
    end
  end

  class InkscapeResolution
    attr_reader :width, :height

    def initialize(width, height, unit="uu")
      @width = width.kind_of?(InkscapeUnit) ? width : InkscapeUnit.new(width, unit)
      @height = height.kind_of?(InkscapeUnit) ? height : InkscapeUnit.new(height, unit)
    end

    def scale(f)
      InkscapeResolution.new(@width.scale(f), @height.scale(f))
    end

    def to_s
      "#{@width.to_s}x#{@height.to_s}"
    end
  end

  class InkscapeRemote
    attr_reader :inkscape_version

    def initialize
      @inkscape_version = probe_inkscape_version
      open_shell
      yield self
    ensure
      quit
    end

    def is_windows
      @is_windows ||= (RbConfig::CONFIG['host_os'] =~ /mswin|mingw|cygwin/) != nil
    end

    def open(args)
      if is_windows
        # Inkscape on Windows for some reason needs to run from its binary dir.
        # popen2e so get stdout and stderr in one pipe. inkscape 1 shell seems to
        # use both as output and we need to read to not block it.
        Open3.popen2e(*[File.basename(self.class.path)] + args,
                                       :chdir => File.dirname(self.class.path))
      else
        Open3.popen2e(*[self.class.path] + args)
      end
    end

    def response
      if @inkscape_version == 0
        o = @out.read(1)
        if o == ">"
          puts "1> #{o}" if Inkmake.verbose
          return :prompt;
        end
      else
        o = @out.read(2)
        if o == "> "
          puts "1> #{o}" if Inkmake.verbose
          return :prompt;
        end
      end
      o = o + @out.readline
      puts "2> '#{o}'" if Inkmake.verbose
      o
    end

    def wait_prompt
      loop do
        case response
        when :prompt then break
        end
      end
    end

    def open_shell
      @in, @out = open(["--shell"])
      wait_prompt
    end

    def command0(args)
      c = args.collect do |key, value|
        if value
          "\"#{key}=#{self.class.escape value.to_s}\""
        else
          key
        end
      end.join(" ")
      puts "< #{c}" if Inkmake.verbose
      @in.write "#{c}\n"
      @in.flush
    end

    def command1(args)
      c = args.collect do |key, value|
        if value
          "#{key}:#{value.to_s}"
        else
          "#{key}:"
        end
      end.join("\n")
      puts "< #{c}" if Inkmake.verbose
      @in.write "#{c}\n"
      @in.flush
    end

    def probe_inkscape_version
      _in, out = open(["--version"])
      version = 0
      begin
        loop do
          case out.readline()
          when /^\s*Inkscape 1\..*$/ then
            version = 1
          when /^\s*Inkscape 0\..*$/ then
            version = 0
          end
        end
      rescue EOFError
      end
      version
    end

    def export0(opts)
      c = {
        "--file" => opts[:svg_path],
        "--export-#{opts[:format]}" => opts[:out_path]
      }
      if opts[:res]
        s = opts[:rotate_scale_hack] ? 2 : 1
        c["--export-width"] = opts[:res].width.to_pixels(opts[:dpi] || 90) * s
        c["--export-height"] = opts[:res].height.to_pixels(opts[:dpi] || 90) * s
      end
      if opts[:dpi]
        c["--export-dpi"] = opts[:dpi]
      end
      if opts[:area].kind_of? Array
        c["--export-area"] = ("%f:%f:%f:%f" % opts[:area])
      elsif opts[:area] == :drawing
        c["--export-area-drawing"] = nil
      elsif opts[:area].kind_of? String
        c["--export-id"] = opts[:area]
      end
      command0(c)
      width, height = [0, 0]
      loop do
        case response
        when /^Area .* exported to (\d+) x (\d+) pixels.*$/ then
          width = $1
          height = $2
        when :prompt then break
        end
      end

      [width, height]
    end

    def export1(opts)
      c = [
        ["file-open", opts[:svg_path]],
        ["export-type", opts[:format]],
        ["export-filename", opts[:out_path]]
      ]
      if opts[:res]
        s = opts[:rotate_scale_hack] ? 2 : 1
        c += [["export-width", opts[:res].width.to_pixels(opts[:dpi] || 90) * s]]
        c += [["export-height", opts[:res].height.to_pixels(opts[:dpi] || 90) * s]]
      else
        c += [["export-width", ""]]
        c += [["export-height", ""]]
      end
      if opts[:dpi]
        c += [["export-dpi", opts[:dpi]]]
      end

      c += [["export-area", ""]]
      c += [["export-area-drawing", "false"]]
      c += [["export-id", ""]]
      c += [["export-area-page", "false"]]

      if opts[:area].kind_of? Array
        c += [["export-area", ("%f:%f:%f:%f" % opts[:area])]]
      elsif opts[:area] == :drawing
        c += [["export-area-drawing", "true"]]
      elsif opts[:area].kind_of? String
        c += [["export-id", opts[:area]]]
      else
        c += [["export-area-page", "true"]]
      end
      c.each do |a|
        command1([a])
        wait_prompt
      end

      command1([["export-do"]])
      width, height = [0, 0]
      loop do
        case response
        when /^Area .* exported to (\d+) x (\d+) pixels.*$/ then
          width = $1
          height = $2
        when :prompt then break
        end
      end
      command1([["file-close"]])
      wait_prompt

      [width, height]
    end

    def export(opts)
      if @inkscape_version == 0 then
        export0(opts)
      else
        export1(opts)
      end
    end

    def query_all(file)
      ids = []
      if @inkscape_version == 0 then
        command0({
          "--file" => file,
          "--query-all" => nil,
        })
      else
        command1([["file-open", file]])
        wait_prompt
        command1([["query-all", file]])
      end
      loop do
        case response
        when /^(.*),(.*),(.*),(.*),(.*)$/ then ids << [$1, $2.to_f, $3.to_f, $4.to_f, $5.to_f]
        when :prompt then break
        end
      end
      if @inkscape_version == 1 then
        command1([["file-close", file]])
        wait_prompt
      end
      ids
    end

    def ids(file)
      Hash[query_all(file).map {|l| [l[0], l[1..-1]]}]
    end

    def drawing_area(file)
      query_all(file).first[1..-1]
    end

    def quit
      if @inkscape_version == 0 then
        command0({"quit" => nil})
      else
        @in.close
      end
      @out.read
      nil
    end

    def self.escape(s)
      s.gsub(/([\\"'])/, '\\\\\1')
    end

    def self.path
      return Inkmake.inkscape_path if Inkmake.inkscape_path

      # try to figure out inkscape path
      p = ( 
        (["/Applications/Inkscape.app/Contents/MacOS/inkscape",
          "/Applications/Inkscape.app/Contents/Resources/bin/inkscape",
          'c:\Program Files\Inkscape\inkscape.exe',
          'c:\Program Files (x86)\Inkscape\inkscape.exe'] +
          (ENV['PATH'].split(':').map {|p| File.join(p, "inkscape")}))
        .select do |path|
          File.exists? path
        end)
      .first
      if p
        p
      else
        begin
          require "osx/cocoa"
          app_path = OSX::NSWorkspace.sharedWorkspace.fullPathForApplication:"Inkscape"
          ["#{app_path}/Contents/MacOS/inkscape",
           "#{app_path}/Contents/Resources/bin/inkscape"]
          .select do |path|
            File.exists? path
          end
        rescue NameError, LoadError
          nil
        end
      end
    end
  end

  class InkFile
    attr_reader :svg_path, :out_path
    DefaultVariants = {
      "@2x" => {:scale => 2.0}
    }
    Rotations = {
      "right" => 90,
      "left" => -90,
      "upsidedown" => 180
    }
    # 123x123, 12.3cm*12.3cm
    RES_RE = /^(\d+(?:\.\d+)?(?:px|pt|pc|mm|cm|dm|m|in|ft|uu)?)[x*](\d+(?:\.\d+)?(?:px|pt|pc|mm|cm|dm|m|in|ft|uu)?)$/
    # *123, *1.23
    SCALE_RE = /^\*(\d+(?:\.\d+)?)$/
    # 180dpi
    DPI_RE = /^(\d+(?:\.\d+)?)dpi$/i
    # (prefix)[(...)](suffix)
    DEST_RE = /^([^\[]*)(?:\[(.*)\])?(.*)$/
    # test.svg, test.SVG
    SVG_RE = /\.svg$/i
    # ext to format, supported inkscape output formats
    EXT_RE = /\.(png|pdf|ps|eps)$/i
    # supported inkscape output formats
    FORMAT_RE = /^(png|pdf|ps|eps)$/i
    # @name
    AREA_NAME_RE = /^@(.*)$/
    # @x:y:w:h
    AREA_SPEC_RE = /^@(\d+(?:\.\d+)?):(\d+(?:\.\d+)?):(\d+(?:\.\d+)?):(\d+(?:\.\d+)?)$/
    # right, left, upsidedown
    ROTATE_RE = /^(right|left|upsidedown)$/
    # show/hide layer or id, "+Layer 1", +#id, -*
    SHOWHIDE_RE = /^([+-])(.+)$/

    class SyntaxError < StandardError
    end

    class ProcessError < StandardError
    end

    def initialize(file, opts)
      @file = file
      @images = []
      @force = opts[:force]

      svg_path = nil
      out_path = nil
      File.read(file).lines.each_with_index do |line, index|
        line.strip!
        next if line.empty? or line.start_with? "#"
        begin
          case line
          when /^svg:(.*)/i then svg_path = File.expand_path($1.strip, File.dirname(file))
          when /^out:(.*)/i then out_path = File.expand_path($1.strip, File.dirname(file))
          else
            @images << InkImage.new(self, parse_line(line))
          end
        rescue SyntaxError => e
          puts "#{file}:#{index+1}: #{e.message}"
          exit
        end
      end

      # order is: argument, config in inkfile, inkfile directory
      @svg_path = opts[:svg_path] || svg_path || File.dirname(file)
      @out_path = opts[:out_path] || out_path || File.dirname(file)
    end

    def parse_split_line(line)
      # changed CSV API in ruby 1.9
      if RUBY_VERSION.start_with? "1.8"
        CSV::parse_line(line, fs = " ")
      else
        CSV::parse_line(line, **{:col_sep => " "})
      end
    end

    def parse_line(line)
      cols = nil
      begin
        cols = parse_split_line(line)
      rescue CSV::MalformedCSVError => e
        raise SyntaxError, e.message
      end
      raise SyntaxError, "Invalid number of columns" if cols.count < 1

      if not DEST_RE.match(cols[0])
        raise SyntaxError, "Invalid destination format \"#{cols[0]}\""
      end

      opts = {}
      opts[:prefix] = $1
      variants = $2
      opts[:suffix] = $3
      opts[:format] = $1.downcase if EXT_RE.match(opts[:prefix] + opts[:suffix])

      cols[1..-1].each do |col|
        case col
        when RES_RE then opts[:res] = InkscapeResolution.new($1, $2, "px")
        when SVG_RE then opts[:svg] = col
        when AREA_SPEC_RE then opts[:area] = [$1.to_f, $2.to_f, $3.to_f, $4.to_f]
        when AREA_NAME_RE then opts[:area] = $1
        when /^drawing$/ then opts[:area] = :drawing
        when FORMAT_RE then opts[:format] = $1.downcase
        when ROTATE_RE then opts[:rotate] = Rotations[$1]
        when SCALE_RE then opts[:scale] = $1.to_f
        when DPI_RE then opts[:dpi] = $1.to_f
        when SHOWHIDE_RE
          op = $1 == "+" ? :show : :hide
          if $2.start_with? "#"
            type = :id
            name= $2[1..-1]
          else
            type = :layer
            name = $2 == "*" ? :all : $2
          end
          (opts[:showhide] ||= []).push({:op => op, :type => type, :name => name})
        else
          raise SyntaxError, "Unknown column \"#{col}\""
        end
      end

      if not opts[:format]
        raise SyntaxError, "Unknown or no output format could be determined"
      end

      variants = (variants.split("|") if variants) || []
      opts[:variants] = variants.collect do |variant|
        name, options = variant.split("=", 2)
        if options
          options = Hash[
            options.split(",").map do |option|
            case option
            when ROTATE_RE then [:rotate, Rotations[$1]]
            when RES_RE then [:res, InkscapeResolution.new($1, $2, "px")]
            when SCALE_RE then [:scale, $1.to_f]
            when DPI_RE then [:dpi, $1.to_f]
            else
              raise SyntaxError, "Invalid variant option \"#{option}\""
            end
            end
          ]
        else
          options = DefaultVariants[name]
          raise SyntaxError, "Invalid default variant \"#{name}\"" if not options
        end

        [name, options]
      end

      opts
    end

    def variants_to_generate
      l = []
      @images.each do |image|
        image.variants.each do |variant|
          next if not @force and
          File.exists? variant.out_path and
          File.mtime(variant.out_path) > File.mtime(image.svg_path) and
          File.mtime(variant.out_path) > File.mtime(@file)
          if variant.out_path == image.svg_path
            raise ProcessError, "Avoiding overwriting source SVG file #{image.svg_path}"
          end

          l << variant
        end
      end

      l
    end

    def temp_rotate_svg(path, degrees, width, height)
      if degrees != 180
        out_width, out_height = height, width
      else
        out_width, out_height = width, height
      end
      file_href = "file://#{path}"
      svg =
        "<?xml version=\"1.0\"?>" +
        "<svg xmlns:xlink=\"http://www.w3.org/1999/xlink\" width=\"#{out_width}\" height=\"#{out_height}\">" +
        "<g>" +
        "<image transform=\"translate(#{out_width/2} #{out_height/2}) rotate(#{degrees})\"" +
        "  width=\"#{width}\" height=\"#{height}\" x=\"#{-width/2}\" y=\"#{-height/2}\"" +
          "  xlink:href=#{file_href.encode(:xml => :attr)} />" +
        "</g>" +
          "</svg>"
        f = Tempfile.new(["inkmake", ".svg"])
        f.write(svg)
        f.flush
        f.seek(0)
        [f, out_width, out_height]
    end

    def process
      variants = variants_to_generate
      if variants.empty?
        return false
      end

      idfilemap = {}
      InkscapeRemote.new do |inkscape|
        variants.each do |variant|
          if not File.exists? variant.image.svg_path
            raise ProcessError, "Source SVG file #{variant.image.svg_path} does not exist"
          end

          out_res = nil
          # order: 200x200, @id/area, svg res
          if variant.image.res
            out_res = variant.image.res
          elsif variant.image.area == :drawing
            res = inkscape.drawing_area(variant.image.svg_path)
            out_res = InkscapeResolution.new(res[2], res[3], "uu")
          elsif variant.image.area
            if variant.image.area.kind_of? String
              if not idfilemap.has_key? variant.image.svg_path
                idfilemap[variant.image.svg_path] = inkscape.ids(variant.image.svg_path)
              end

              if not idfilemap[variant.image.svg_path].has_key? variant.image.area
                raise ProcessError, "Unknown id \"#{variant.image.area}\" in file #{variant.image.svg_path} when exporting #{variant.out_path}"
              end

              res = idfilemap[variant.image.svg_path][variant.image.area]
              out_res = InkscapeResolution.new(res[2], res[3], "uu")
            else
              a = variant.image.area
              # x0:y0:x1:y1
              out_res = InkscapeResolution.new(a[2]-a[0], a[3]-a[1], "uu")
            end
          else
            out_res = variant.image.svg_res
          end

          scale = variant.options[:scale]
          if scale
            out_res = out_res.scale(scale)
          end

          out_res = variant.options[:res] if variant.options[:res]

          rotate = (variant.image.format == "png" and variant.options[:rotate])

          FileUtils.mkdir_p File.dirname(variant.out_path)

          svg_path = variant.image.svg_path
          if variant.image.showhide
            svg_path = variant.image.svg_showhide_file.path
          end

          res = inkscape.export({
            :svg_path => svg_path,
            :out_path => variant.out_path,
            :res => out_res,
            :dpi => variant.options[:dpi],
            :format => variant.image.format,
            :area => variant.image.area,
            :rotate_scale_hack => rotate
          })

          if rotate
            tmp, width, height = temp_rotate_svg(variant.out_path, rotate, res[0].to_i, res[1].to_i)
            res = inkscape.export({
              :svg_path => tmp.path,
              :out_path => variant.out_path,
              :res => InkscapeResolution.new(width / 2, height / 2, "px"),
              :format => variant.image.format
            })
            tmp.close!
          end

          rel_path = Pathname.new(variant.out_path).relative_path_from(Pathname.new(Dir.pwd))
          if variant.image.format == "png"
            puts "#{rel_path} #{res[0]}x#{res[1]}"
          else
            puts rel_path
          end
        end
      end

      return true
    end
  end

  class InkImage
    attr_reader :inkfile, :prefix, :variants, :suffix, :res, :format, :area, :showhide

    def initialize(inkfile, opts)
      @inkfile = inkfile
      @prefix = opts[:prefix]
      variant_opts = {
        :rotate => opts[:rotate],
        :scale => opts[:scale],
        :dpi => opts[:dpi]
      }
      @variants = [InkVariant.new(self, "", variant_opts)]
      opts[:variants].each do |name, options|
        @variants << InkVariant.new(self, name, options)
      end
      @suffix = opts[:suffix]
      @res = opts[:res]
      @svg = opts[:svg]
      @format = opts[:format]
      @area = opts[:area]
      @showhide = opts[:showhide]
    end

    def svg_path
      File.expand_path(@svg || File.basename(@prefix + @suffix, ".*") + ".svg", inkfile.svg_path)
    end

    def svg_res
      @svg_res ||=
        begin
          doc = REXML::Document.new File.read(svg_path)
          svgattr = doc.elements.to_a("//svg")[0].attributes
          if svgattr["width"] and svgattr["height"]
            InkscapeResolution.new(svgattr["width"], svgattr["height"], "uu")
          else
            nil
          end
        end
    end

    def svg_showhide_file
      @svg_showhide_file ||=
        begin
          doc = REXML::Document.new File.read(svg_path)

          layers = {}
          REXML::XPath.each(doc, "//svg:g[@inkscape:groupmode='layer']").each do |e|
            label = e.attributes["label"]
            next if not label
            layers[label] = e
          end

          ids = {}
          REXML::XPath.each(doc, "//svg:*[@id]").each do |e|
            id = e.attributes["id"]
            next if not id
            ids[id] = e
          end

          @showhide.each do |sh|
            elms = nil
            if sh[:type] == :layer
              if sh[:name] == :all
                elms = layers.values
              else
                e = layers[sh[:name]]
                if not e
                  raise InkFile::ProcessError, "Layer \"#{sh[:name]}\" not found in #{svg_path}"
                end
                elms = [e]
              end
            else
              e = ids[sh[:name]]
              if not e
                raise InkFile::ProcessError, "Id \"#{sh[:name]}\" not found in #{svg_path}"
              end
              elms = [e]
            end

            elms.each do |e|
              # NOTE: should be visibility for #ids to not affect flow etc?
              e.delete_attribute("display")
              # also remove display inside style attributes
              if e.attributes["style"]
                style_declarations = e.attributes["style"].split(";")
                style_declarations_to_keep = []
                style_declarations.each do | sd |
                  property, value = sd.split(":", 2)
                if value && property == "display"
                  # throw it out
                else
                  style_declarations_to_keep.push(sd)
                end
                end
                e.attributes["style"] = style_declarations_to_keep.join(";")
              end
              if sh[:op] == :hide
                e.add_attribute("display", "none")
              else
                # show is a nop
              end
            end
          end

          f = Tempfile.new(["inkmake", ".svg"])
          doc.write(:output => f)
          f.flush
          f
        end
    end
  end

  class InkVariant
    attr_reader :image, :name, :options

    def initialize(image, name, options)
      @image = image
      @name = name
      @options = options
    end

    def out_path
      File.expand_path(
        "#{@image.prefix}#{@name}#{@image.suffix}",
        @image.inkfile.out_path)
    end
  end

  def self.run(argv)
    inkfile_path = nil
    inkfile_opts = {}
    OptionParser.new do |o|
      o.banner = "Usage: #{$0} [options] [Inkfile]"
      o.on("-v", "--verbose", "Verbose output") { @verbose = true }
      o.on("-s", "--svg PATH", "SVG source base path") { |v| inkfile_opts[:svg_path] = v }
      o.on("-o", "--out PATH", "Output base path") { |v| inkfile_opts[:out_path] = v }
      o.on("-f", "--force", "Force regenerate (skip time check)") { |v| inkfile_opts[:force] = true }
      o.on("-i", "--inkscape PATH", "Inkscape binary path", "Default: #{InkscapeRemote.path || "not found"}") { |v| @inkscape_path = v }
      o.on("-h", "--help", "Display help") { puts o; exit }
      begin
        inkfile_path = o.parse!(argv).first
      rescue OptionParser::InvalidOption => e
        puts e.message
        exit 1
      end
    end

    inkfile_path = File.expand_path(inkfile_path || "Inkfile", Dir.pwd)

    begin
      raise "Could not find Inkscape binary (maybe try --inkscape?)" if not InkscapeRemote.path
      raise "Inkscape binary #{InkscapeRemote.path} does not exist or is not executable" if not InkscapeRemote.path or not File.executable? InkscapeRemote.path
    rescue StandardError => e
      puts e.message
      exit 1
    end

    begin
      if not InkFile.new(inkfile_path, inkfile_opts).process
        puts "Everything seems to be up to date"
      end
    rescue InkFile::ProcessError, SystemCallError => e
      puts e.message
      exit 1
    end
  end
end
