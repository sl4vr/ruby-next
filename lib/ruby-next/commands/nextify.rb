# frozen_string_literal: true

require "fileutils"
require "pathname"

require "ruby-next/language"

module RubyNext
  module Commands
    class Nextify < Base
      using RubyNext

      attr_reader :lib_path, :paths, :out_path, :min_version, :single_version

      def run
        log "RubyNext core strategy: #{RubyNext::Core.strategy}"
        log "RubyNext transpile mode: #{RubyNext::Language.mode}"

        remove_rbnext!

        paths.each do |path|
          contents = File.read(path)
          transpile path, contents
        end
      end

      def parse!(args)
        print_help = false
        @min_version = MIN_SUPPORTED_VERSION
        @single_version = false

        optparser = base_parser do |opts|
          opts.banner = "Usage: ruby-next nextify DIRECTORY_OR_FILE [options]"

          opts.on("-o", "--output=OUTPUT", "Specify output directory or file or stdout") do |val|
            @out_path = val
          end

          opts.on("--min-version=VERSION", "Specify the minimum Ruby version to support") do |val|
            @min_version = Gem::Version.new(val)
          end

          opts.on("--single-version", "Only create one version of a file (for the earliest Ruby version)") do
            @single_version = true
          end

          opts.on("--edge", "Enable edge (master) Ruby features") do |val|
            require "ruby-next/language/edge"
          end

          opts.on("--proposed", "Enable proposed/experimental Ruby features") do |val|
            require "ruby-next/language/proposed"
          end

          opts.on(
            "--transpile-mode=MODE",
            "Transpiler mode (ast or rewrite). Default: ast"
          ) do |val|
            Language.mode = val.to_sym
          end

          opts.on("--[no-]refine", "Do not inject `using RubyNext`") do |val|
            Core.strategy = :core_ext unless val
          end

          opts.on("-h", "--help", "Print help") do
            print_help = true
          end
        end

        optparser.parse!(args)

        @lib_path = args[0]

        if print_help
          $stdout.puts optparser.help
          exit 0
        end

        unless lib_path&.then(&File.method(:exist?))
          $stdout.puts "Path not found: #{lib_path}"
          $stdout.puts optparser.help
          exit 2
        end

        @paths =
          if File.directory?(lib_path)
            Dir[File.join(lib_path, "**/*.rb")]
          elsif File.file?(lib_path)
            [lib_path].tap do |_|
              @lib_path = File.dirname(lib_path)
            end
          end
      end

      private

      def transpile(path, contents, version: min_version)
        rewriters = Language.rewriters.select { |rw| rw.unsupported_version?(version) }

        context = Language::TransformContext.new

        new_contents = Language.transform contents, context: context, rewriters: rewriters

        return unless context.dirty?

        versions = context.sorted_versions
        version = versions.shift

        # First, store already transpiled contents in the minimum required version dir
        save new_contents, path, version

        return if versions.empty? || single_version?

        # Then, generate the source code for the next version
        transpile path, contents, version: version
      end

      def save(contents, path, version)
        return $stdout.puts(contents) if stdout?

        paths = [Pathname.new(path).relative_path_from(Pathname.new(lib_path))]

        paths.unshift(version.segments[0..1].join(".")) unless single_version?

        next_path =
          if next_dir_path.end_with?(".rb")
            out_path
          else
            File.join(next_dir_path, *paths)
          end

        unless CLI.dry_run?
          FileUtils.mkdir_p File.dirname(next_path)

          File.write(next_path, contents)
        end

        log "Generated: #{next_path}"
      end

      def remove_rbnext!
        return if CLI.dry_run? || stdout?

        return unless File.directory?(next_dir_path)

        log "Remove old files: #{next_dir_path}"
        FileUtils.rm_r(next_dir_path)
      end

      def next_dir_path
        @next_dir_path ||= (out_path || File.join(lib_path, RUBY_NEXT_DIR))
      end

      def stdout?
        out_path == "stdout"
      end

      alias single_version? single_version
    end
  end
end
