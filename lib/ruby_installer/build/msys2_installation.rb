require "rbconfig"

module RubyInstaller
module Build # Use for: Build, Runtime
  # :nodoc:
  class Msys2Installation
    MSYS2_INSTALL_KEY = "SOFTWARE/Microsoft/Windows/CurrentVersion/Uninstall/"

    class MsysNotFound < RuntimeError
    end
    class CommandError < RuntimeError
    end

    attr_reader :mingwdir

    def initialize(msys_path=nil)
      @msys_path = msys_path
      @msys_path_fixed = true if msys_path
      @mingwdir = nil
    end

    def reset_cache
      @msys_path = nil unless @msys_path_fixed
    end

    def iterate_msys_paths
      # Prefer MSYS2 when installed within the ruby directory.
      yield File.join(RbConfig::TOPDIR, "msys64")
      yield File.join(RbConfig::TOPDIR, "msys32")

      # Then try MSYS2 next to the ruby directory.
      yield File.join(File.dirname(RbConfig::TOPDIR), "msys64")
      yield File.join(File.dirname(RbConfig::TOPDIR), "msys32")

      # If msys2 is installed at the default location
      yield "c:/msys64"
      yield "c:/msys32"

      # If msys2 is installed per installer.exe
      require "win32/registry"
      begin
        Win32::Registry::HKEY_CURRENT_USER.open(backslachs(MSYS2_INSTALL_KEY)) do |reg|
          reg.each_key do |subkey|
            subreg = reg.open(subkey)
            if subreg['DisplayName'] =~ /^MSYS2 / && File.directory?(il=subreg['InstallLocation'])
              yield il
            end
          end
        end
      rescue Win32::Registry::Error
      end

      ENV['PATH'].split(";").each do |path|
        # If /path/to/msys64 is in the PATH (e.g. Chocolatey)
        yield path
      end

      raise MsysNotFound, "MSYS2 could not be found"
    end

    def msys_path
      @msys_path ||= begin
        iterate_msys_paths do |path|
          if File.exist?(File.join(path, "usr/bin/msys-2.0.dll"))
            break backslachs(path)
          end
        end
      end
    end

    def msys_bin_path
      backslachs( File.join(msys_path, "/usr/bin") )
    end

    def msystem
      RUBY_PLATFORM=~/x64/ ? 'MINGW64' : 'MINGW32'
    end

    def mingw_bin_path(mingwarch=nil)
      backslachs( File.join(msys_path, mingwarch || msystem, "bin") )
    end

    def mingw_prefix
      "/#{msystem.downcase}"
    end

    def mingw_package_prefix
      RUBY_PLATFORM=~/x64/ ? "mingw-w64-x86_64" : "mingw-w64-i686"
    end

    def enable_dll_search_paths
      @mingwdir ||= begin
        DllDirectory.set_defaults
        path = mingw_bin_path
        DllDirectory.new(path)
      rescue MsysNotFound
        # We silently ignore this error to allow Ruby installations without MSYS2.
      end
    end

    def disable_dll_search_paths
      @mingwdir.remove if @mingwdir
      @mingwdir = nil
    end

    private def backslachs(path)
      path.gsub("/", "\\")
    end

    private def ruby_bin_dir
      require "rbconfig"
      backslachs( File.join(RbConfig::TOPDIR, "bin") )
    end

    private def msys_apps_envvars(mingwarch=nil)
      vars = {}
      msys_bin = msys_bin_path
      mingw_bin = mingw_bin_path(mingwarch)
      ruby_bin = ruby_bin_dir

      vars['PATH'] = ruby_bin + ";" + mingw_bin + ";" + msys_bin
      vars['RI_DEVKIT'] = msys_path
      vars['MSYSTEM'] = (mingwarch || msystem).upcase
      vars['PKG_CONFIG_PATH'] = "#{mingw_prefix}/lib/pkgconfig:#{mingw_prefix}/share/pkgconfig"
      vars['ACLOCAL_PATH'] = "#{mingw_prefix}/share/aclocal:/usr/share/aclocal"
      vars['MANPATH'] = "#{mingw_prefix}/share/man"
      vars['MINGW_PACKAGE_PREFIX'] = mingw_package_prefix

      vars
    end

    private def with_msys_install_hint(if_no_msys = :hint)
      case if_no_msys
      when :hint
        begin
          yield
        rescue MsysNotFound
          $stderr.puts "MSYS2 could not be found. Please run 'ridk install'"
          $stderr.puts "or download and install MSYS2 manually from https://msys2.github.io/"
          exit 1
        end
      when :raise
        yield
      else
        raise ArgumentError, "invalid value #{if_no_msys.inspect} for variable if_no_msys"
      end
    end

    def enable_msys_apps(mingwarch: nil, if_no_msys: :hint, for_gem_install: false)
      vars = with_msys_install_hint(if_no_msys) do
        msys_apps_envvars(mingwarch)
      end

      changed = false

      if (path=vars.delete("PATH")) && !ENV['PATH'].include?(path)
        phrase = "Temporarily enhancing PATH for MSYS/MINGW..."
        if for_gem_install && defined?(Gem)
          Gem.ui.say(phrase) if Gem.configuration.verbose
        elsif $DEBUG
          $stderr.puts phrase
        end
        changed = true
        ENV['PATH'] = path + ";" + ENV['PATH']
      end
      vars.each do |key, val|
        changed = true if ENV[key] != val
        ENV[key] = val
      end

      changed
    end

    def disable_msys_apps(mingwarch: nil, if_no_msys: :hint)
      vars = with_msys_install_hint(if_no_msys) do
        msys_apps_envvars(mingwarch)
      end
      if path=vars.delete("PATH")
        ENV['PATH'] = ENV['PATH'].gsub(path + ";", "")
      end
      vars.each do |key, val|
        ENV.delete(key)
      end
    end

    def with_msys_apps_enabled
      changed = enable_msys_apps
      begin
        yield
      ensure
        disable_msys_apps if changed
      end
    end

    # This method is used for the ridk command.
    def enable_msys_apps_per_cmd
      vars = with_msys_install_hint{ msys_apps_envvars }
      if (path=vars.delete("PATH")) && !ENV['PATH'].include?(path)
        vars['PATH'] = path + ";" + ENV['PATH']
      end
      vars.map do |key, val|
        "#{key}=#{val}"
      end.join("\n")
    end

    # This method is used for the ridk command.
    def disable_msys_apps_per_cmd
      vars = with_msys_install_hint{ msys_apps_envvars }
      str = "".dup
      if path=vars.delete("PATH")
        str << "PATH=#{ ENV['PATH'].gsub(path + ";", "") }\n"
      end
      str << vars.map do |key, val|
        "#{key}="
      end.join("\n")
    end

    # This method is used for the ridk command.
    def enable_msys_apps_per_ps1
      vars = with_msys_install_hint{ msys_apps_envvars }
      if (path=vars.delete("PATH")) && !ENV['PATH'].include?(path)
        vars['PATH'] = path + ";" + ENV['PATH']
      end
      vars.map do |key, val|
        "$env:#{key}=\"#{val.gsub('"', '`"')}\""
      end.join(";")
    end

    # This method is used for the ridk command.
    def disable_msys_apps_per_ps1
      vars = with_msys_install_hint{ msys_apps_envvars }
      str = "".dup
      if path=vars.delete("PATH")
        str << "$env:PATH=\"#{ ENV['PATH'].gsub(path + ";", "").gsub('"', '`"') }\";"
      end
      str << vars.map do |key, val|
        "$env:#{key}=''"
      end.join(";")
    end

    def install_packages(packages, verbose: false)
      return if packages.empty?

      with_msys_apps_enabled do
        Gem.ui.say("Installing required msys2 packages: #{packages.join(" ")}") if verbose

        args = ["pacman", "-S", "--needed", "--noconfirm", *packages]
        Gem.ui.say("> #{args.join(" ")}") if verbose==1

        res = IO.popen(args, &:read)
        raise CommandError, "pacman failed with the following output:\n#{res}" if !$? || $?.exitstatus != 0

        Gem.ui.say(res) if verbose==1
      end
    end

    def install_mingw_packages(packages, verbose: false)
      packages = packages.map{|pack| "#{mingw_package_prefix}-#{pack}" }
      install_packages(packages, verbose: verbose)
    end
  end
end
end
